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

  ## Options

    * `:path` — directory for recording files (default: `"priv/replay_recordings"`)
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

  @recording_ext ".recording"
  @summary_ext ".summary"
  @part_ext ".part"
  @tmp_ext ".tmp"

  @impl true
  def save(%Recording{} = recording, opts) do
    with {:ok, recording_path} <- path(recording.id, @recording_ext, opts),
         {:ok, summary_path} <- path(recording.id, @summary_ext, opts),
         :ok <- File.mkdir_p(dir(opts)),
         :ok <- write_synced(recording_path, Codec.encode(recording)),
         :ok <- write_synced(summary_path, Codec.encode(Summary.new(recording))) do
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
    case File.ls(dir(opts)) do
      {:ok, files} ->
        files
        |> Enum.filter(&(Path.extname(&1) == @summary_ext))
        |> Enum.flat_map(&read_summary(Path.join(dir(opts), &1)))
        |> Enum.sort_by(& &1.connected_at, :desc)

      {:error, :enoent} ->
        []
    end
  end

  @impl true
  def delete(id, opts) do
    with {:ok, summary_path} <- path(id, @summary_ext, opts),
         {:ok, recording_path} <- path(id, @recording_ext, opts),
         :ok <- remove(summary_path),
         :ok <- remove(recording_path) do
      remove_parts(id, opts)
    end
  end

  @impl true
  def clear(opts) do
    case File.ls(dir(opts)) do
      {:ok, files} ->
        files
        |> Enum.filter(&(Path.extname(&1) in [@summary_ext, @recording_ext, @part_ext]))
        |> Enum.each(&remove(Path.join(dir(opts), &1)))

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

  defp read_summary(path) do
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

  defp dir(opts), do: Keyword.get(opts, :path, "priv/replay_recordings")
end
