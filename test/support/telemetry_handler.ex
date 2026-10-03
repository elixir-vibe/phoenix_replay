defmodule PhoenixReplay.Test.TelemetryHandler do
  @moduledoc "Forwards PhoenixReplay telemetry events to the attaching test process."

  @events [
    [:phoenix_replay, :recording, :persisted],
    [:phoenix_replay, :recording, :discarded],
    [:phoenix_replay, :recording, :failed]
  ]

  @doc "Attaches a handler sending `{:telemetry, event, metadata}` to the caller."
  @spec attach(term()) :: :ok
  def attach(id) do
    :ok = :telemetry.attach_many(id, @events, &__MODULE__.handle_event/4, self())
    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(id) end)
  end

  @doc "Telemetry handler forwarding the event name and metadata to `pid`."
  @spec handle_event([atom()], map(), map(), pid()) :: :ok
  def handle_event([:phoenix_replay, :recording, kind], _measurements, metadata, pid) do
    send(pid, {:telemetry, kind, metadata})
    :ok
  end
end
