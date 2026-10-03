defmodule PhoenixReplay.Recorder.Persister do
  @moduledoc """
  Saves a finished recording with retries.

  Runs inside a task started by `PhoenixReplay.Recorder.Monitor`, so the
  backoff sleeps block only that task. Attempts and backoff come from the
  `:persist` configuration; the delay grows linearly with the attempt number.
  """

  require Logger

  alias PhoenixReplay.{Config, Recording, Storage}

  @doc "Saves `recording`, retrying until it succeeds or attempts run out."
  @spec persist(Recording.t(), Config.t()) :: :ok | {:error, term()}
  def persist(%Recording{} = recording, %Config{} = config), do: attempt(recording, config, 1)

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
