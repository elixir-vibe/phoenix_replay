defmodule PhoenixReplay.Recorder.Flusher do
  @moduledoc """
  Writes a running session's buffered events to storage as one chunk.

  Runs in a task started by `PhoenixReplay.Recorder.Monitor`, which flushes
  each session at most once at a time, so a session's chunks are written in
  order by one process. The chunk is redacted with the session's
  `PhoenixReplay.Redactor` before it is written, then its events leave the
  buffer, keeping memory bounded however long the session runs.
  """

  alias PhoenixReplay.{Redactor, Storage}
  alias PhoenixReplay.Recorder.Buffer

  @doc "Flushes the buffered events of session `id`."
  @spec flush(PhoenixReplay.Recording.id()) :: :ok | {:error, term()}
  def flush(id) do
    with {:ok, config} <- Buffer.config(id),
         {:ok, recording} <- Buffer.meta(id),
         [_ | _] = chunk <- Buffer.pending(id),
         {seqs, events} = Enum.unzip(chunk),
         {:ok, redacted} <- redact(%{recording | events: events}, config.redact),
         :ok <-
           Storage.append(
             config.storage,
             %{redacted | events: []},
             Enum.zip(seqs, redacted.events)
           ) do
      Buffer.flushed(id, chunk)
    else
      [] -> :ok
      :error -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp redact(recording, redactor) do
    case Redactor.redact_recording(recording, redactor) do
      {:ok, redacted} -> {:ok, redacted}
      {:error, _reason} -> {:error, :redaction_failed}
    end
  end
end
