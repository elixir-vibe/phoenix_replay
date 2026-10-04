defmodule PhoenixReplay.Recording.TimelineTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Event, Timeline}
  alias PhoenixReplay.Test.Fixtures

  defp recording(events), do: %Recording{id: "r", view: V, connected_at: 0, events: events}

  test "assigns_at/2 starts from mount assigns and merges renders" do
    recording =
      recording([
        %Event{at: 0, type: :mount, data: %{assigns: %{a: 0}}},
        %Event{at: 1, type: :render, data: %{assigns: %{a: 1, b: 1}}},
        %Event{at: 2, type: :event, data: %{name: "x", params: %{}}},
        %Event{at: 3, type: :render, data: %{assigns: %{b: 2}}}
      ])

    assert Timeline.assigns_at(recording, 0) == %{a: 0}
    assert Timeline.assigns_at(recording, 2) == %{a: 1, b: 1}
    assert Timeline.assigns_at(recording, 3) == %{a: 1, b: 2}
  end

  test "duration, indexes and clamping" do
    recording = Fixtures.counter_recording(clicks: 2)

    assert Timeline.duration_ms(recording) == 2001
    assert Timeline.last_index(recording) == 5
    assert Timeline.first_render_index(recording) == 1
    assert Timeline.clamp(recording, -3) == 0
    assert Timeline.clamp(recording, 99) == 5
    assert %Event{type: :event} = Timeline.event_at(recording, 2)
    assert Timeline.duration_ms(recording([])) == 0
    assert Timeline.last_index(recording([])) == 0
  end

  test "viewport_at/2 follows viewport events from the connected viewport" do
    vp = fn width -> %{width: width, height: 800, dpr: 1} end

    recording = %{
      recording([
        %Event{at: 0, type: :mount, data: %{assigns: %{}}},
        %Event{at: 1, type: :viewport, data: vp.(800)},
        %Event{at: 2, type: :event, data: %{name: "x", params: %{}}}
      ])
      | client: %{viewport: vp.(1200), user_agent: nil, tab: nil, referer: nil}
    }

    assert Timeline.viewport_at(recording, 0) == vp.(1200)
    assert Timeline.viewport_at(recording, 2) == vp.(800)
    assert Timeline.viewport_at(recording([]), 0) == nil
  end

  test "url_at/2 follows navigation from the URL the session started on" do
    recording = %{
      recording([
        %Event{at: 0, type: :mount, data: %{assigns: %{}}},
        %Event{at: 1, type: :params, data: %{params: %{}, uri: "http://x/b"}},
        %Event{at: 2, type: :event, data: %{name: "x", params: %{}}}
      ])
      | url: "http://x/a"
    }

    assert Timeline.url_at(recording, 0) == "http://x/a"
    assert Timeline.url_at(recording, 2) == "http://x/b"
  end
end
