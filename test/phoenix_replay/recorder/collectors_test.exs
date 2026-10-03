defmodule PhoenixReplay.Recorder.CollectorsTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Config, Recordings}
  alias PhoenixReplay.Recorder.{Buffer, Collectors}
  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Storage
  alias PhoenixReplay.Test.{Fixtures, Sessions}
  alias PhoenixReplay.Test.Live.TelemetryPage

  defmodule Raising do
    @moduledoc false
    @behaviour PhoenixReplay.Collector

    @impl true
    def events(_opts), do: [PhoenixReplay.Test.Live.TelemetryPage.event()]

    @impl true
    def capture(_event, _measurements, %{source: "raise"}, _opts), do: raise("boom")
    def capture(_event, _measurements, _metadata, _opts), do: :skip
  end

  setup context do
    config =
      Config.new(
        collect: [{TelemetryPage.event(), metadata: [:source, :password], limit: 2}, Raising]
      )

    :ok = Collectors.attach(config, context.test)

    failures = {context.test, :failures}
    test = self()

    :telemetry.attach(
      failures,
      [:phoenix_replay, :collector, :exception],
      fn _event, _measurements, metadata, _config ->
        send(test, {:collector_failed, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(failures)
      Collectors.detach(context.test)
      Storage.clear(Fixtures.storage())
    end)

    Sessions.setup_sessions(context)
  end

  defp collected(id) do
    {:ok, recording} = Buffer.fetch(id)
    Enum.filter(recording.events, &(&1.type == :telemetry))
  end

  test "records events emitted by the LiveView after the event causing them",
       %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/telemetry")
    view |> render_hook("work", %{"source" => "orders"})

    {:ok, recording} = Buffer.fetch(id)
    types = Enum.map(recording.events, & &1.type)
    assert Enum.drop_while(types, &(&1 != :event)) |> Enum.take(2) == [:event, :telemetry]

    assert [
             %Event{
               data: %{
                 event: [:phoenix_replay_test, :work, :stop],
                 summary: "phoenix_replay_test.work.stop",
                 measurements: %{duration: 5.0},
                 metadata: %{source: "orders", password: "[FILTERED]"},
                 error: nil
               }
             }
           ] = collected(id)
  end

  test "records events emitted by tasks the LiveView started", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/telemetry")
    view |> render_hook("async", %{"source" => "async"})
    render_async(view)

    assert [%Event{data: %{metadata: %{source: "async"}}}] = collected(id)
  end

  test "ignores events from processes outside recorded sessions", %{sessions: sessions} do
    {:ok, _view, _html, id} = Sessions.live(sessions, build_conn(), "/telemetry")
    :telemetry.execute(TelemetryPage.event(), %{}, %{source: "elsewhere"})

    assert collected(id) == []
  end

  test "leaves text to the redactor, which reading the session applies", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/telemetry")
    view |> render_hook("work", %{"source" => "card-4242"})

    assert [%Event{data: %{metadata: %{source: "card-4242"}}}] = collected(id)

    assert {:ok, %{events: events}} = Recordings.fetch(Config.load(), id)

    assert %Event{data: %{metadata: %{source: "[REDACTED]"}}} =
             Enum.find(events, &(&1.type == :telemetry))
  end

  test "counts events beyond the limit as dropped", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/telemetry")
    for _ <- 1..5, do: render_hook(view, "work", %{"source" => "orders"})

    assert length(collected(id)) == 2
    assert {:ok, %{dropped: %{"phoenix_replay_test.work.stop" => 3}}} = Buffer.fetch(id)
    assert render(view) =~ ~s(<span id="done">5</span>)
  end

  test "reports a raising collector and keeps it attached", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/telemetry")
    view |> render_hook("work", %{"source" => "raise"})
    view |> render_hook("work", %{"source" => "raise"})

    assert_received {:collector_failed, %{collector: Raising, kind: :error}}
    assert_received {:collector_failed, %{collector: Raising, kind: :error}}
    assert length(collected(id)) == 2
  end
end
