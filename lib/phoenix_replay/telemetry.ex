defmodule PhoenixReplay.Telemetry do
  @moduledoc """
  Telemetry events emitted by PhoenixReplay.

  Each event is emitted once its effect is complete: the session is no
  longer buffered and, for `:persisted`, the recording is in storage.

    * `[:phoenix_replay, :recording, :persisted]` — a recording was saved.
      Measurements: `%{event_count: integer, duration_ms: integer}`.
      Metadata: `%{id: String.t(), view: module}`.
    * `[:phoenix_replay, :recording, :discarded]` — a session ended and was
      not saved, because it had no user interaction or was not sampled by
      `keep: [rate: ...]`. Metadata: `%{id: String.t(), reason:
      :not_interactive | :not_sampled}`.
    * `[:phoenix_replay, :recording, :failed]` — a recording could not be
      saved and was dropped. Metadata: `%{id: String.t(), reason: term}`.
    * `[:phoenix_replay, :recording, :recovered]` — a session whose node
      stopped before it ended was saved from its chunks when the
      application started. Measurements and metadata as for `:persisted`.

  Collector failures are emitted where they happen:

    * `[:phoenix_replay, :collector, :exception]` — a
      `PhoenixReplay.Collector` or the log handler raised while handling an
      event, which was not recorded. Metadata: `%{collector: module, event:
      [atom], kind: atom, reason: term, stacktrace: list}`.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Keep, Summary, Timeline}

  @doc "Emits `[:phoenix_replay, :recording, :persisted]`."
  @spec persisted(Recording.t()) :: :ok
  def persisted(%Recording{} = recording) do
    :telemetry.execute(
      [:phoenix_replay, :recording, :persisted],
      %{
        event_count: Summary.event_count(recording.events),
        duration_ms: Timeline.duration_ms(recording)
      },
      %{id: recording.id, view: recording.view}
    )
  end

  @doc "Emits `[:phoenix_replay, :recording, :recovered]`."
  @spec recovered(Recording.t()) :: :ok
  def recovered(%Recording{} = recording) do
    :telemetry.execute(
      [:phoenix_replay, :recording, :recovered],
      %{
        event_count: Summary.event_count(recording.events),
        duration_ms: Timeline.duration_ms(recording)
      },
      %{id: recording.id, view: recording.view}
    )
  end

  @doc "Emits `[:phoenix_replay, :recording, :discarded]`."
  @spec discarded(Recording.id(), Keep.reason()) :: :ok
  def discarded(id, reason) do
    :telemetry.execute([:phoenix_replay, :recording, :discarded], %{}, %{id: id, reason: reason})
  end

  @doc "Emits `[:phoenix_replay, :recording, :failed]`."
  @spec failed(Recording.id(), term()) :: :ok
  def failed(id, reason) do
    :telemetry.execute([:phoenix_replay, :recording, :failed], %{}, %{id: id, reason: reason})
  end

  @doc "Emits `[:phoenix_replay, :collector, :exception]`."
  @spec collector_failed(module(), [atom()], atom(), term(), Exception.stacktrace()) :: :ok
  def collector_failed(collector, event, kind, reason, stacktrace) do
    :telemetry.execute([:phoenix_replay, :collector, :exception], %{}, %{
      collector: collector,
      event: event,
      kind: kind,
      reason: reason,
      stacktrace: stacktrace
    })
  end
end
