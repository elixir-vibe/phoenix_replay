defmodule PhoenixReplay.Web.Player.EventsTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Web.Player.Events

  test "labels events" do
    event = fn type, data -> Events.label(%Event{at: 0, type: type, data: data}) end

    assert event.(:event, %{name: "save", params: %{}}) == "save"

    assert event.(:event, %{
             name: "validate",
             params: %{"_target" => ["user"], "user" => %{"name" => "Dan"}}
           }) ==
             "validate: name=Dan"

    assert event.(:event, %{name: "add", params: %{}, target: {MyApp.Item, "pear"}}) ==
             "add → MyApp.Item#pear"

    assert event.(:params, %{params: %{}, uri: "/a"}) == "navigate → /a"
    assert event.(:info, %{tag: :tick}) == "handle_info :tick"
    assert event.(:info, %{tag: nil}) == "handle_info"
    assert event.(:render, %{assigns: %{b: 1, a: 2}}) == "assigns a, b"

    query = %{event: [:repo, :query], summary: "SELECT 1", measurements: %{}, metadata: %{}}
    assert event.(:telemetry, Map.put(query, :error, nil)) == "SELECT 1"
    assert event.(:telemetry, %{query | summary: nil} |> Map.put(:error, nil)) == "repo.query"
    assert event.(:telemetry, Map.put(query, :error, "timeout")) == "SELECT 1 — timeout"
    assert event.(:log, %{level: :warning, message: "slow", metadata: %{}}) == "[warning] slow"

    assert event.(:exit, %{reason: "** (RuntimeError) boom\n    stack"}) ==
             "exited: ** (RuntimeError) boom"
  end

  test "groups events into kinds, LiveView first" do
    recording = %Recording{
      id: "r",
      view: View,
      connected_at: 0,
      events: [
        %Event{at: 0, type: :log, data: %{level: :error, message: "", metadata: %{}}},
        %Event{at: 1, type: :mount},
        %Event{at: 2, type: :render, data: %{assigns: %{}}}
      ],
      dropped: %{"repo.query" => 3}
    }

    assert Events.kinds(recording) == ["liveview", "logs"]
    assert Events.error_count(recording) == 1
    assert Events.dropped_count(recording) == 3
    assert Events.collected?(hd(recording.events))
  end

  test "marks errors" do
    error = %Event{at: 0, type: :log, data: %{level: :error, message: "", metadata: %{}}}
    assert Events.marker_class(error) == "size-2 bg-error"
    assert Events.marker_class(%Event{at: 0, type: :params}) == "size-1.5 bg-kind-nav"
  end
end
