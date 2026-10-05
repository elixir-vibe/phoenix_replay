defmodule PhoenixReplay.Session.Finalizer do
  @moduledoc """
  Completes a finished recording and saves it with retries.

  Runs inside a task started by `PhoenixReplay.Session.Monitor`, so
  redaction and the backoff sleeps block only that task. The events still
  in the buffer are redacted with the session's `PhoenixReplay.Redactor`
  and joined to the chunks already flushed to storage, see
  `PhoenixReplay.Recordings.complete/3`. If that fails, nothing is saved. Attempts and backoff come from the
  `:persist` configuration; the delay grows linearly with the attempt number.
  """

  require Logger

  alias PhoenixReplay.{Config, Recording, Recordings, Storage, Telemetry}
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
    :ok = Recordings.broadcast_change()

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
    with {:ok, complete} <- Recordings.complete(recording, config),
         :ok <- attempt(complete, config, 1) do
      {:ok, complete}
    else
      {:error, reason} ->
        Logger.error("PhoenixReplay: dropping recording #{recording.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

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

  # A backend that raises instead of returning an error is retried too.
  defp save(storage, recording) do
    Storage.save(storage, recording)
  rescue
    error -> {:error, error}
  end
end
