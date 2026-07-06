defmodule PhoenixReplay.Storage.File do
  @moduledoc """
  File-based storage backend. Writes one serialized file per recording.

  ## Options

    * `:path` — directory to store recordings (default: `"priv/replay_recordings"`)
    * `:format` — `:etf` (default) or `:json`
  """

  @behaviour PhoenixReplay.Storage

  alias PhoenixReplay.Storage.Serializer

  defp dir(opts), do: Keyword.get(opts, :path, "priv/replay_recordings")
  defp format(opts), do: Keyword.get(opts, :format, :etf)

  @impl true
  def init(opts) do
    File.mkdir_p!(dir(opts))
    :ok
  end

  @impl true
  def save(recording, opts) do
    with {:ok, data} <- Serializer.encode(recording, format(opts)) do
      path = file_path(recording.id, opts)
      File.write(path, data)
    end
  end

  @impl true
  def get(id, opts) do
    path = file_path(id, opts)

    with {:ok, data} <- File.read(path),
         {:ok, recording} <- Serializer.decode(data, format(opts)) do
      {:ok, recording}
    else
      _ -> :error
    end
  end

  @impl true
  def list(opts) do
    base = dir(opts)

    case File.ls(base) do
      {:ok, files} ->
        files
        |> Enum.flat_map(fn filename ->
          id = strip_extensions(filename)

          case get(id, opts) do
            {:ok, recording} -> [recording]
            :error -> []
          end
        end)
        |> Enum.sort_by(& &1.connected_at, :desc)

      {:error, _} ->
        []
    end
  end

  @impl true
  def list_summaries(opts) do
    opts
    |> list()
    |> Enum.map(&PhoenixReplay.Recordings.summary/1)
  end

  @impl true
  def delete(id, opts) do
    path = file_path(id, opts)
    File.rm(path)
    :ok
  end

  @impl true
  def clear(opts) do
    base = dir(opts)

    case File.ls(base) do
      {:ok, files} ->
        Enum.each(files, fn filename -> File.rm(Path.join(base, filename)) end)
        :ok

      {:error, _} ->
        :ok
    end
  end

  defp file_path(id, opts) do
    basename = Path.basename(id)
    Path.join(dir(opts), basename <> Serializer.extension(format(opts)))
  end

  defp strip_extensions(filename) do
    filename
    |> String.replace_suffix(".etf", "")
    |> String.replace_suffix(".json", "")
  end
end
