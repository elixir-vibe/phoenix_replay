defmodule PhoenixReplay.Storage.File do
  @moduledoc """
  Stores each recording as two files in a directory.

  `<id>.recording` holds the full recording and `<id>.summary` holds its
  `PhoenixReplay.Recording.Summary`, so listing never decodes recordings.
  The summary is written last and deleted first: a summary file always points
  at a complete recording. Both are written to a temporary file, synced and
  renamed into place, so a crash never leaves half a recording.

  While a session runs, its chunks are appended to `<id>.<node>.part` as
  frames (see `PhoenixReplay.Storage.Codec.frame/1`), and saving the
  finished recording deletes the part file. Part files carry a tag of the
  node and host that wrote them, so instances sharing a directory, in a
  cluster or not, only recover their own. Parts left by an instance that
  never starts again under the same node and host name are not recovered.

  Summaries are kept in an ETS index once read, so listing reads only the
  summary files it has not seen. The directory's file names stay the
  source of truth: files another node wrote or deleted are picked up on
  the next list.

  ## Options

    * `:path` — directory for recording files (default: `"priv/replay_recordings"`).
      A relative path is resolved against the working directory when
      PhoenixReplay started, not when a file is written: the working
      directory belongs to the whole VM, and tools such as Phoenix's code
      reloader change it while they compile a path dependency.
    * `:sync` — whether to sync each appended chunk to disk. A plain write
      survives a crash of the node; syncing also survives losing power or
      the operating system, at a cost per chunk. Defaults to `false`.
      Finished recordings are always synced.
  """

  @behaviour PhoenixReplay.Storage

  require Logger

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Summary
  alias PhoenixReplay.Storage.Codec
  alias PhoenixReplay.Storage.File.Index

  @recording_ext ".recording"
  @summary_ext ".summary"
  @part_ext ".part"
  @tmp_ext ".tmp"

  @impl true
  def child_spec(opts), do: Index.child_spec(opts)

  @impl true
  def save(%Recording{} = recording, opts) do
    with {:ok, recording_path} <- path(recording.id, @recording_ext, opts),
         {:ok, summary_path} <- path(recording.id, @summary_ext, opts),
         :ok <- File.mkdir_p(dir(opts)),
         :ok <- write_synced(recording_path, Codec.encode(recording)),
         summary = Summary.new(recording, saved_at: System.system_time(:millisecond)),
         :ok <- write_synced(summary_path, Codec.encode(summary)) do
      Index.put(dir(opts), [{recording.id, summary}])
      remove_parts(recording.id, opts)
    end
  end

  @impl true
  def append(%Recording{} = recording, chunk, opts) do
    with {:ok, part_path} <- part_path(recording.id, opts),
         :ok <- File.mkdir_p(dir(opts)),
         {:ok, fd} <- :file.open(part_path, [:append, :raw, :binary]) do
      try do
        with :ok <- :file.write(fd, Codec.frame({%{recording | events: []}, chunk})) do
          if Keyword.get(opts, :sync, false), do: :file.datasync(fd), else: :ok
        end
      after
        :file.close(fd)
      end
    end
  end

  @impl true
  def fetch_partial(id, opts) do
    with {:ok, part_path} <- part_path(id, opts),
         {:ok, binary} <- read(part_path) do
      case Codec.decode_frames(binary) do
        [] -> {:error, :not_found}
        frames -> {:ok, merge(frames)}
      end
    end
  end

  @impl true
  def partials(opts) do
    suffix = "." <> node_tag() <> @part_ext

    case File.ls(dir(opts)) do
      {:ok, files} ->
        for file <- files,
            String.ends_with?(file, suffix),
            do: String.replace_suffix(file, suffix, "")

      {:error, :enoent} ->
        []
    end
  end

  @impl true
  def fetch(id, opts) do
    with {:ok, path} <- path(id, @recording_ext, opts),
         {:ok, binary} <- read(path) do
      Codec.decode(binary, Recording)
    end
  end

  @impl true
  def list(opts) do
    dir = dir(opts)

    ids =
      case File.ls(dir) do
        {:ok, files} ->
          for file <- files, Path.extname(file) == @summary_ext, do: Path.rootname(file)

        {:error, :enoent} ->
          []
      end

    dir
    |> summaries(ids)
    |> Summary.sort()
  end

  @impl true
  def delete(id, opts) do
    with {:ok, summary_path} <- path(id, @summary_ext, opts),
         {:ok, recording_path} <- path(id, @recording_ext, opts),
         :ok <- remove(summary_path),
         :ok = Index.delete(dir(opts), id),
         :ok <- remove(recording_path) do
      remove_parts(id, opts)
    end
  end

  @impl true
  def clear(opts) do
    dir = dir(opts)
    :ok = Index.clear(dir)

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&(Path.extname(&1) in [@summary_ext, @recording_ext, @part_ext]))
        |> Enum.each(&remove(Path.join(dir, &1)))

      {:error, :enoent} ->
        :ok
    end
  end

  # The latest metadata wins; events are ordered by sequence number, since
  # concurrent writers can append a later number to an earlier chunk.
  defp merge(frames) do
    {recording, chunks} =
      Enum.reduce(frames, {nil, []}, fn {recording, chunk}, {_previous, chunks} ->
        {recording, [chunk | chunks]}
      end)

    events =
      chunks
      |> Enum.concat()
      |> Enum.sort_by(fn {seq, _event} -> seq end)
      |> Enum.map(fn {_seq, event} -> event end)

    Recording.upgrade(%{recording | events: events})
  end

  defp write_synced(path, data) do
    tmp_path = path <> @tmp_ext

    with {:ok, fd} <- :file.open(tmp_path, [:write, :raw, :binary]),
         :ok <- write_and_close(fd, data) do
      :file.rename(tmp_path, path)
    end
  end

  defp write_and_close(fd, data) do
    with :ok <- :file.write(fd, data), do: :file.datasync(fd)
  after
    :file.close(fd)
  end

  defp remove_parts(id, opts) do
    dir(opts)
    |> Path.join(id <> ".*" <> @part_ext)
    |> Path.wildcard()
    |> Enum.each(&remove/1)
  end

  defp part_path(id, opts) do
    if Recording.valid_id?(id),
      do: {:ok, Path.join(dir(opts), id <> "." <> node_tag() <> @part_ext)},
      else: {:error, :not_found}
  end

  # Nodes that are not distributed are all :nonode@nohost, so the host
  # tells instances sharing a directory apart.
  defp node_tag do
    {:ok, host} = :inet.gethostname()
    {node(), host} |> :erlang.phash2() |> Integer.to_string(36)
  end

  defp read_summary(dir, id) do
    path = Path.join(dir, id <> @summary_ext)

    with {:ok, binary} <- File.read(path),
         {:ok, summary} <- Codec.decode(binary, Summary) do
      [summary]
    else
      error ->
        Logger.warning("PhoenixReplay: skipping unreadable #{path}: #{inspect(error)}")
        []
    end
  end

  defp read(path) do
    case File.read(path) do
      {:error, :enoent} -> {:error, :not_found}
      result -> result
    end
  end

  defp remove(path) do
    case File.rm(path) do
      {:error, :enoent} -> :ok
      result -> result
    end
  end

  defp path(id, ext, opts) do
    if Recording.valid_id?(id),
      do: {:ok, Path.join(dir(opts), id <> ext)},
      else: {:error, :not_found}
  end

  defp dir(opts) do
    opts
    |> Keyword.get(:path, "priv/replay_recordings")
    |> Path.expand(Index.root())
  end

  # Reads the summaries of `ids`: from the index where it has them, from
  # disk otherwise. Files other nodes removed leave the index too.
  defp summaries(dir, ids) do
    listed = MapSet.new(ids)
    {indexed, gone} = dir |> Index.summaries() |> Enum.split_with(&MapSet.member?(listed, &1.id))
    Enum.each(gone, &Index.delete(dir, &1.id))

    known = MapSet.new(indexed, & &1.id)

    read =
      for id <- ids,
          not MapSet.member?(known, id),
          summary <- read_summary(dir, id),
          do: {id, summary}

    :ok = Index.put(dir, read)
    indexed ++ Enum.map(read, &elem(&1, 1))
  end
end
