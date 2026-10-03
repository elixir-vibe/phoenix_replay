defmodule PhoenixReplay.Recorder.Persister do
  @moduledoc """
  Redacts a finished recording and saves it with retries.

  Runs inside a task started by `PhoenixReplay.Recorder.Monitor`, so
  redaction and the backoff sleeps block only that task. The recording is
  redacted once with the session's `PhoenixReplay.Redactor`; if redaction
  fails, nothing is saved. Attempts and backoff come from the
  `:persist` configuration; the delay grows linearly with the attempt number.
  """

  require Logger

  alias PhoenixReplay.{Config, Recording, Redactor, Storage}

  @doc "Redacts and saves `recording`, retrying the save until it succeeds or attempts run out."
  @spec persist(Recording.t(), Config.t()) :: :ok | {:error, term()}
  def persist(%Recording{} = recording, %Config{} = config) do
    case redact(recording, config.redact) do
      {:ok, redacted} ->
        attempt(redacted, config, 1)

      {:error, reason} ->
        Logger.error("PhoenixReplay: dropping recording #{recording.id}: redaction failed")
        {:error, {:redaction_failed, reason}}
    end
  end

  defp redact(recording, nil), do: {:ok, recording}
  defp redact(recording, redactor), do: Redactor.redact_recording(recording, redactor)

  defp attempt(recording, config, attempt) do
    case Storage.save(config.storage, recording) do
      :ok ->
        :ok

      {:error, _reason} when attempt < config.persist.attempts ->
        Process.sleep(config.persist.backoff * attempt)
        attempt(recording, config, attempt + 1)

      {:error, reason} ->
        Logger.error("PhoenixReplay: dropping recording #{recording.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
