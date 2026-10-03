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
end
