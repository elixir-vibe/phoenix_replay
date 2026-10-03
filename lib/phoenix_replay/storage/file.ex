defmodule PhoenixReplay.Storage.File do
  @moduledoc """
  Stores each recording as two files in a directory.

  `<id>.recording` holds the full recording and `<id>.summary` holds its
  `PhoenixReplay.Recording.Summary`, so listing never decodes recordings.
  The summary is written last and deleted first: a summary file always points
  at a complete recording.

  ## Options

    * `:path` — directory for recording files (default: `"priv/replay_recordings"`)
  """

  @behaviour PhoenixReplay.Storage

  require Logger

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Summary
  alias PhoenixReplay.Storage.Codec

  @recording_ext ".recording"
  @summary_ext ".summary"

  @impl true
  def save(%Recording{} = recording, opts) do
    with {:ok, recording_path} <- path(recording.id, @recording_ext, opts),
         {:ok, summary_path} <- path(recording.id, @summary_ext, opts),
         :ok <- File.mkdir_p(dir(opts)),
         :ok <- File.write(recording_path, Codec.encode(recording)) do
      File.write(summary_path, Codec.encode(Summary.new(recording)))
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
         :ok <- remove(summary_path) do
      remove(recording_path)
    end
  end

  @impl true
  def clear(opts) do
    case File.ls(dir(opts)) do
      {:ok, files} ->
        files
        |> Enum.filter(&(Path.extname(&1) in [@summary_ext, @recording_ext]))
        |> Enum.each(&remove(Path.join(dir(opts), &1)))

      {:error, :enoent} ->
        :ok
    end
  end

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
