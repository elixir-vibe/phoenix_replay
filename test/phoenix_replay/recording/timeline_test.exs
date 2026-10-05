defmodule PhoenixReplay.Recording.TimelineTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Event, Timeline}
  alias PhoenixReplay.Test.Fixtures

  defp recording(events), do: %Recording{id: "r", view: V, connected_at: 0, events: events}

  test "starts from mount assigns and merges renders" do
    recording =
      recording([
        %Event{at: 0, type: :mount, data: %{assigns: %{a: 0}}},
        %Event{at: 1, type: :render, data: %{assigns: %{a: 1, b: 1}}},
        %Event{at: 2, type: :event, data: %{name: "x", params: %{}}},
        %Event{at: 3, type: :render, data: %{assigns: %{b: 2}}}
      ])

    assert Timeline.at(recording, 0).assigns == %{a: 0, phoenix_replay_state: %{}}
    assert Timeline.at(recording, 2).assigns == %{a: 1, b: 1, phoenix_replay_state: %{}}
    assert Timeline.at(recording, 3).assigns == %{a: 1, b: 2, phoenix_replay_state: %{}}
  end

  test "duration, indexes and clamping" do
    recording = Fixtures.counter_recording(clicks: 2)

    assert Timeline.duration_ms(recording) == 2001
    assert Timeline.last_index(recording) == 5
    assert Timeline.first_render_index(recording) == 1
    assert Timeline.at(recording, -3).index == 0
    assert Timeline.at(recording, 99).index == 5
    assert %Event{type: :event} = Timeline.at(recording, 2).event
    assert %Event{type: :render} = recording |> Timeline.at(2) |> Timeline.next()
    assert recording |> Timeline.at(5) |> Timeline.next() == nil
    assert Timeline.duration_ms(recording([])) == 0
    assert Timeline.last_index(recording([])) == 0
    assert %Timeline{index: 0, event: nil} = Timeline.at(recording([]), 3)
  end

  test "follows viewport events from the connected viewport" do
    vp = fn width -> %{width: width, height: 800, dpr: 1} end

    recording = %{
      recording([
        %Event{at: 0, type: :mount, data: %{assigns: %{}}},
        %Event{at: 1, type: :viewport, data: vp.(800)},
        %Event{at: 2, type: :event, data: %{name: "x", params: %{}}}
      ])
      | client: %PhoenixReplay.Recording.Client{viewport: vp.(1200)}
    }

    assert Timeline.at(recording, 0).viewport == vp.(1200)
    assert Timeline.at(recording, 2).viewport == vp.(800)
    assert Timeline.at(recording([]), 0).viewport == nil
  end

  test "follows navigation from the URL the session started on" do
    recording = %{
      recording([
        %Event{at: 0, type: :mount, data: %{assigns: %{}}},
        %Event{at: 1, type: :params, data: %{params: %{}, uri: "http://x/b"}},
        %Event{at: 2, type: :event, data: %{name: "x", params: %{}}}
      ])
      | url: "http://x/a"
    }

    assert Timeline.at(recording, 0).url == "http://x/a"
    assert Timeline.at(recording, 2).url == "http://x/b"
  end

  test "seeking forward applies only the events in between, and back starts over" do
    recording = Fixtures.counter_recording(clicks: 2)
    timeline = Timeline.new(recording)

    for {path, last} <- [{[5, 1], 1}, {[1, 3, 5], 5}, {[5, 5, 0, 4], 4}] do
      walked = Enum.reduce(path, timeline, &Timeline.seek(&2, &1))
      assert walked == Timeline.at(recording, last)
    end
  end
end
