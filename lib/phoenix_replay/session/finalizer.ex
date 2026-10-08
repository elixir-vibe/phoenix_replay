defmodule PhoenixReplay.Session.Finalizer do
  @moduledoc """
  Completes a finished recording and saves it with retries.

  Runs inside a task started by `PhoenixReplay.Session.Monitor`, so
  redaction and the backoff sleeps block only that task. The events still
  in the buffer are redacted with the session's `PhoenixReplay.Redactor`
  and joined to the chunks already flushed to storage, see `complete/3`.
  If that fails, nothing is saved.
  Attempts and backoff come from the `:persist` configuration; the delay
  grows linearly with the attempt number.
  """

  require Logger

  alias PhoenixReplay.{Catalog, Config, Recording, Redactor, Storage, Telemetry}
  alias PhoenixReplay.Session.Buffer

  @doc """
  Saves the buffered `recording` with `persist/2`, then closes its buffer
  and emits `[:phoenix_replay, :recording, :persisted]` or `:failed`.

  The task does this itself, so a session is finished even if the monitor
  that started the task restarts meanwhile.
  """
  @spec finish(Recording.t(), Config.t()) :: {:ok, Recording.t()} | {:error, term()}
  def finish(%Recording{id: id} = recording, %Config{} = config) do
    result = persist(recording, config)
    :ok = Buffer.close(id)
    :ok = Catalog.broadcast_change()

    case result do
      {:ok, saved} -> Telemetry.persisted(saved)
      {:error, reason} -> Telemetry.failed(id, reason)
    end

    result
  end

  @doc """
  Completes and saves the buffered `recording`, retrying the save until it
  succeeds or attempts run out. Returns the saved recording.
  """
  @spec persist(Recording.t(), Config.t()) :: {:ok, Recording.t()} | {:error, term()}
  def persist(%Recording{} = recording, %Config{} = config) do
    with {:ok, complete} <- complete(recording, config),
         :ok <- attempt(complete, config, 1) do
      {:ok, complete}
    else
      {:error, reason} ->
        Logger.error("PhoenixReplay: dropping recording #{recording.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Completes a buffered session's recording, for saving it or for showing
  it while it runs: redacts the events still in the buffer and puts the
  chunks already flushed to storage, which were redacted when they were
  written, before them.

  Takes the `:progress` option of
  `PhoenixReplay.Redactor.redact_recording/3`.
  """
  @spec complete(Recording.t(), Config.t(), keyword()) :: {:ok, Recording.t()} | {:error, term()}
  def complete(%Recording{} = recording, %Config{} = config, opts \\ []) do
    with {:ok, redacted} <- Redactor.redact_recording(recording, config.redact, opts),
         {:ok, flushed} <- flushed_events(recording.id, config.storage) do
      events = flushed ++ redacted.events

      {:ok,
       %{
         redacted
         | events: events,
           code: Recording.Code.with_modules(redacted.code, components(events))
       }}
    end
  end

  # The LiveComponents the session rendered, whose code it was made with too.
  defp components(events),
    do: for(%{type: :component, data: %{module: module}} <- events, uniq: true, do: module)

  defp attempt(recording, config, attempt) do
    case save(config.storage, recording) do
      :ok ->
        :ok

      {:error, _reason} when attempt < config.persist.attempts ->
        Process.sleep(config.persist.backoff * attempt)
        attempt(recording, config, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A backend that raises, as Ecto does when the database is unreachable,
  # is retried like one that returns an error.
  defp save(storage, recording) do
    Storage.save(storage, recording)
  rescue
    # reach:disable-next-line bare_rescue -- a storage backend may raise anything
    exception -> {:error, exception}
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
end
