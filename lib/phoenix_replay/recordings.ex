defmodule PhoenixReplay.Recordings do
  @moduledoc """
  Reads and deletes recordings across the live buffer and storage.

  A recording is in exactly one place: `PhoenixReplay.Recorder.Buffer`
  while its session runs and until it is saved, storage afterwards.
  Changes are broadcast on `PhoenixReplay.PubSub` so the dashboard can
  refresh without polling.

  Stored recordings were redacted when they were saved. Sessions still in
  the buffer are redacted here, with their session's `PhoenixReplay.Redactor`,
  so everything read through this module shows the same values.
  """

  alias PhoenixReplay.{Config, Recording, Redactor, Storage}
  alias PhoenixReplay.Recorder.Buffer
  alias PhoenixReplay.Recording.Summary

  @topic "phoenix_replay:recordings"

  @doc "Lists buffered then stored recordings, each most recent first."
  @spec list(Config.t()) :: [Summary.t()]
  def list(%Config{storage: storage}) do
    buffered = Enum.map(Buffer.summaries(), &redact_url/1)
    buffered_ids = MapSet.new(buffered, & &1.id)
    buffered ++ Enum.reject(Storage.list(storage), &MapSet.member?(buffered_ids, &1.id))
  end

  @doc """
  Fetches a recording from the buffer or storage.

  A buffered session is redacted first, which can take a while with a
  detecting `PhoenixReplay.Redactor`. Pass `progress: fun` to be called
  with the number of events redacted so far and the total.
  """
  @spec fetch(Config.t(), Recording.id(), keyword()) :: {:ok, Recording.t()} | {:error, term()}
  def fetch(%Config{storage: storage}, id, opts \\ []) do
    with {:ok, recording} <- Buffer.fetch(id),
         {:ok, config} <- Buffer.config(id) do
      complete(recording, config, Keyword.get(opts, :progress, fn _done, _total -> :ok end))
    else
      :error -> Storage.fetch(storage, id)
    end
  end

  @doc """
  Completes a buffered session's recording: redacts the events still in the
  buffer and puts the chunks already flushed to storage, which were
  redacted when they were written, before them.

  `progress` is called as the buffered events are redacted.
  """
  @spec complete(Recording.t(), Config.t(), Redactor.progress()) ::
          {:ok, Recording.t()} | {:error, term()}
  def complete(
        %Recording{} = recording,
        %Config{} = config,
        progress \\ fn _done, _total -> :ok end
      ) do
    with {:ok, redacted} <- redact(recording, config.redact, progress),
         {:ok, flushed} <- flushed_events(recording.id, config.storage) do
      {:ok, %{redacted | events: flushed ++ redacted.events}}
    end
  end

  # Events written concurrently can reach the buffer after a later one was
  # flushed; they follow the flushed events here, microseconds out of order.
  defp flushed_events(id, storage) do
    if Buffer.flushed?(id) do
      with {:ok, partial} <- Storage.fetch_partial(storage, id), do: {:ok, partial.events}
    else
      {:ok, []}
    end
  end

  @doc "Returns true while the session `id` is in the buffer and has not been saved."
  @spec live?(Recording.id()) :: boolean()
  def live?(id), do: Buffer.config(id) != :error

  @doc "Deletes a stored recording."
  @spec delete(Config.t(), Recording.id()) :: :ok | {:error, term()}
  def delete(%Config{storage: storage}, id) do
    with :ok <- Storage.delete(storage, id), do: broadcast_change()
  end

  @doc "Deletes every stored recording."
  @spec clear(Config.t()) :: :ok | {:error, term()}
  def clear(%Config{storage: storage}) do
    with :ok <- Storage.clear(storage), do: broadcast_change()
  end

  @doc "Subscribes the caller to `:recordings_changed` messages."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(PhoenixReplay.PubSub, @topic)

  defp redact(recording, redactor, progress) do
    case Redactor.redact_recording(recording, redactor, progress) do
      {:ok, redacted} -> {:ok, redacted}
      {:error, _reason} -> {:error, :redaction_failed}
    end
  end

  defp redact_url(%Summary{url: nil} = summary), do: summary

  defp redact_url(%Summary{id: id, url: url} = summary) do
    with {:ok, %Config{redact: redactor}} when redactor != nil <- Buffer.config(id),
         {:ok, url} <- Redactor.redact_term(url, redactor) do
      %{summary | url: url}
    else
      {:ok, %Config{redact: nil}} -> summary
      _failed -> %{summary | url: nil}
    end
  end

  @doc "Notifies subscribers that the set of recordings changed."
  @spec broadcast_change() :: :ok
  def broadcast_change do
    Phoenix.PubSub.broadcast(PhoenixReplay.PubSub, @topic, :recordings_changed)
  end
end
