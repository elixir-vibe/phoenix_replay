defmodule PhoenixReplay.Capture.LogsTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Catalog, Config, Storage}
  alias PhoenixReplay.Capture.Logs
  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Test.{Fixtures, Sessions}

  require Logger

  setup context do
    id = :"#{context.test}"
    config = Config.new(logs: [level: :warning, metadata: [:source], limit: 2])
    :ok = Logs.attach(config, id)

    on_exit(fn ->
      Logs.detach(id)
      Storage.clear(Fixtures.storage())
    end)

    Sessions.setup_sessions(context)
  end

  defp logs(id) do
    {:ok, recording} = Buffer.fetch(id)
    Enum.filter(recording.events, &(&1.type == :log))
  end

  defp log(view, level, message),
    do: render_hook(view, "log", %{"level" => level, "message" => message})

  test "records messages logged by the LiveView at or above the level", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/telemetry")

    ExUnit.CaptureLog.capture_log(fn ->
      log(view, "warning", "payment for card-4242 declined")
      log(view, "error", "gateway down")
    end)

    assert [
             %Event{
               data: %{
                 level: :warning,
                 message: "payment for card-4242 declined",
                 metadata: %{source: "page"}
               }
             },
             %Event{data: %{level: :error, message: "gateway down"}} = error
           ] = logs(id)

    assert Event.error?(error)

    # The session's redactor masks the text whenever the session is read.
    assert {:ok, %{events: events}} = Catalog.fetch(Config.load(), id)

    assert %Event{data: %{message: "payment for [REDACTED] declined"}} =
             Enum.find(events, &(&1.type == :log))
  end

  test "ignores messages below the level and outside sessions", %{sessions: sessions} do
    # Let info messages reach the handler, so its own level is what skips them.
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: :warning) end)
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/telemetry")

    ExUnit.CaptureLog.capture_log(fn ->
      Logger.error("from the test process")
      log(view, "info", "routine")
    end)

    assert logs(id) == []
  end

  test "counts messages beyond the limit as dropped", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/telemetry")

    ExUnit.CaptureLog.capture_log(fn ->
      for n <- 1..3, do: log(view, "warning", "attempt #{n}")
    end)

    assert length(logs(id)) == 2
    assert {:ok, %{dropped: %{"log" => 1}}} = Buffer.fetch(id)
  end
end
