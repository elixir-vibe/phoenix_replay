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
  node that wrote them, so nodes sharing a directory only recover their
  own.

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

  import Ex2ms

  require Logger

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Summary
  alias PhoenixReplay.Recordings.Filter
  alias PhoenixReplay.Storage.Codec

  @recording_ext ".recording"
  @summary_ext ".summary"
  @part_ext ".part"
  @tmp_ext ".tmp"
  @index __MODULE__.Index

  @doc """
  Creates the summary index. `PhoenixReplay.Application` calls it at start,
  so the table lives as long as the application; without it, every list
  reads the summary files.
  """
  @spec create_index() :: :ok
  def create_index do
    :ets.new(@index, [:named_table, :public, :set, read_concurrency: true])
    :ok
  end

  @impl true
  def save(%Recording{} = recording, opts) do
    with {:ok, recording_path} <- path(recording.id, @recording_ext, opts),
         {:ok, summary_path} <- path(recording.id, @summary_ext, opts),
         :ok <- File.mkdir_p(dir(opts)),
         :ok <- write_synced(recording_path, Codec.encode(recording)),
         summary = Summary.new(recording),
         :ok <- write_synced(summary_path, Codec.encode(summary)) do
      index(dir(opts), [{recording.id, summary}])
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
    |> Enum.sort_by(& &1.connected_at, :desc)
  end

  @impl true
  def query(filter, page_opts, opts), do: opts |> list() |> Filter.page(filter, page_opts)

  # Reads the summaries of `ids`, from the index where it has them.
  defp summaries(dir, ids) do
    if not indexed?() do
      Enum.flat_map(ids, &read_summary(dir, &1))
    else
      known = :ets.select(@index, fun(do: ({{^dir, id}, _summary} -> id)))
      listed = MapSet.new(ids)

      for id <- known, not MapSet.member?(listed, id), do: unindex(dir, id)

      known = MapSet.new(known)

      index(
        dir,
        for(
          id <- ids,
          not MapSet.member?(known, id),
          [summary] <- [read_summary(dir, id)],
          do: {id, summary}
        )
      )

      :ets.select(@index, fun(do: ({{^dir, _id}, summary} -> summary)))
    end
  end

  defp index(dir, entries) do
    if indexed?(),
      do: :ets.insert(@index, for({id, summary} <- entries, do: {{dir, id}, summary}))

    :ok
  end

  # The index lives with the application; without it, summaries are read
  # from disk every time.
  defp indexed?, do: :ets.whereis(@index) != :undefined

  defp unindex(dir, id) do
    if indexed?(), do: :ets.delete(@index, {dir, id})
    :ok
  end

  @impl true
  def delete(id, opts) do
    with {:ok, summary_path} <- path(id, @summary_ext, opts),
         {:ok, recording_path} <- path(id, @recording_ext, opts),
         :ok <- remove(summary_path),
         :ok = unindex(dir(opts), id),
         :ok <- remove(recording_path) do
      remove_parts(id, opts)
    end
  end

  @impl true
  def clear(opts) do
    dir = dir(opts)
    if indexed?(), do: :ets.match_delete(@index, {{dir, :_}, :_})

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

    %{recording | events: events}
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

  defp node_tag, do: node() |> :erlang.phash2() |> Integer.to_string(36)

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

  @doc """
  Remembers the directory relative `:path`s are resolved against.
  `PhoenixReplay.Application` calls it at start; see the `:path` option.
  """
  @spec remember_root(Path.t()) :: :ok
  def remember_root(dir \\ File.cwd!()), do: :persistent_term.put({__MODULE__, :root}, dir)

  defp dir(opts) do
    opts
    |> Keyword.get(:path, "priv/replay_recordings")
    |> Path.expand(:persistent_term.get({__MODULE__, :root}, nil) || File.cwd!())
  end
end
