defmodule PhoenixReplay.Capture.LiveComponentsHandlerTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Capture.LiveComponents
  alias PhoenixReplay.Config
  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Test.Fixtures

  defmodule RaisingSanitizer do
    def sanitize_params(_params), do: raise("broken sanitizer")
    def sanitize_assigns(assigns), do: assigns
  end

  test "reports a failure instead of raising, so :telemetry keeps the handler" do
    recording = %{Fixtures.counter_recording() | events: []}
    :ok = Buffer.open(recording, self(), Config.new(sanitizer: RaisingSanitizer))
    on_exit(fn -> Buffer.close(recording.id) end)

    metadata = %{
      component: Some.Component,
      socket: %{assigns: %{id: "c"}},
      event: "save",
      params: %{}
    }

    ref =
      :telemetry_test.attach_event_handlers(self(), [[:phoenix_replay, :collector, :exception]])

    on_exit(fn -> :telemetry.detach(ref) end)

    event = [:phoenix, :live_component, :handle_event, :start]
    assert :ok = LiveComponents.handle_event(event, %{}, metadata, nil)

    assert_received {[:phoenix_replay, :collector, :exception], ^ref, %{},
                     %{collector: LiveComponents, event: ^event, reason: %RuntimeError{}}}
  end
end
