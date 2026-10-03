defmodule PhoenixReplay.Telemetry do
  @moduledoc """
  Telemetry events emitted by PhoenixReplay.

  Each event is emitted once its effect is complete: the session is no
  longer buffered and, for `:persisted`, the recording is in storage.

    * `[:phoenix_replay, :recording, :persisted]` — a recording was saved.
      Measurements: `%{event_count: integer, duration_ms: integer}`.
      Metadata: `%{id: String.t(), view: module}`.
    * `[:phoenix_replay, :recording, :discarded]` — a session ended without
      user interaction and was not saved. Metadata: `%{id: String.t()}`.
    * `[:phoenix_replay, :recording, :failed]` — a recording could not be
      saved and was dropped. Metadata: `%{id: String.t(), reason: term}`.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Timeline

  @doc "Emits `[:phoenix_replay, :recording, :persisted]`."
  @spec persisted(Recording.t()) :: :ok
  def persisted(%Recording{} = recording) do
    :telemetry.execute(
      [:phoenix_replay, :recording, :persisted],
      %{event_count: length(recording.events), duration_ms: Timeline.duration_ms(recording)},
      %{id: recording.id, view: recording.view}
    )
  end

  @doc "Emits `[:phoenix_replay, :recording, :discarded]`."
  @spec discarded(Recording.id()) :: :ok
  def discarded(id),
    do: :telemetry.execute([:phoenix_replay, :recording, :discarded], %{}, %{id: id})

  @doc "Emits `[:phoenix_replay, :recording, :failed]`."
  @spec failed(Recording.id(), term()) :: :ok
  def failed(id, reason) do
    :telemetry.execute([:phoenix_replay, :recording, :failed], %{}, %{id: id, reason: reason})
  end
end
