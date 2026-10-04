defmodule PhoenixReplay.Capture.LiveComponentsHandlerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias PhoenixReplay.Capture.LiveComponents
  alias PhoenixReplay.Config
  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Test.Fixtures

  defmodule RaisingSanitizer do
    def sanitize_params(_params), do: raise("broken sanitizer")
    def sanitize_assigns(assigns), do: assigns
  end

  test "logs a failure instead of raising, so :telemetry keeps the handler" do
    recording = %{Fixtures.counter_recording() | events: []}
    :ok = Buffer.open(recording, self(), Config.new(sanitizer: RaisingSanitizer))
    on_exit(fn -> Buffer.close(recording.id) end)

    metadata = %{
      component: Some.Component,
      socket: %{assigns: %{id: "c"}},
      event: "save",
      params: %{}
    }

    log =
      capture_log(fn ->
        assert :ok =
                 LiveComponents.handle_event(
                   [:phoenix, :live_component, :handle_event, :start],
                   %{},
                   metadata,
                   nil
                 )
      end)

    assert log =~ "broken sanitizer"
  end
end
