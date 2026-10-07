defmodule PhoenixReplay.Export.ScheduleTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Export.Schedule
  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Client, Event, PointerTrack}
  alias PhoenixReplay.Test.Fixtures

  @opts [fps: 10, idle: nil, max_dpr: 2, hold: 1_000]

  defp plan(recording, track \\ PointerTrack.empty(), opts \\ []),
    do: Schedule.new(recording, track, Keyword.merge(@opts, opts))

  defp summary(schedule), do: Enum.map(schedule.shots, &{&1.index, &1.at, &1.frames})

  test "shows each event from the first render, holding the last" do
    # The first render is at 5 ms, the clicks render at 1001 and 2001 ms,
    # and the last is held for a second: a frame every 100 ms.
    schedule = plan(Fixtures.counter_recording())

    assert summary(schedule) == [{1, 5, 10}, {3, 1005, 10}, {5, 2005, 9}]
    assert Schedule.frames(schedule) == 29
    assert Schedule.duration_ms(schedule) == 2_900
  end

  test "shortens a stretch without activity to the idle time" do
    recording = %{
      Fixtures.counter_recording(clicks: 0)
      | events: [
          %Event{at: 0, type: :mount, data: %{assigns: %{}}},
          %Event{at: 5, type: :render, data: %{assigns: %{count: 0}}},
          %Event{at: 10_000, type: :event, data: %{name: "inc", params: %{}}},
          %Event{at: 10_001, type: :render, data: %{assigns: %{count: 1}}}
        ]
    }

    # Ten seconds between the render and the click become two: one after
    # the render, one before the click.
    schedule = plan(recording, PointerTrack.empty(), idle: 2_000)

    assert summary(schedule) == [{1, 5, 20}, {2, 10_000, 1}, {3, 10_100, 9}]
    assert Schedule.duration_ms(schedule) == 3_000

    # Without :idle, the wait is shown whole.
    assert Schedule.duration_ms(plan(recording)) == 10_900
  end

  test "gives every frame its own shot while the pointer animates" do
    track = %{PointerTrack.empty() | moves: [[100, 10, 10, 0], [150, 20, 20, 0]]}
    shots = plan(Fixtures.counter_recording(), track).shots

    # The trail fades 500 ms after the last move, at 650 ms.
    assert [%{at: 5, frames: 1} | shots] = shots
    {animated, [settled | _rest]} = Enum.split(shots, 6)
    assert Enum.map(animated, &{&1.at, &1.frames}) == for(at <- 105..605//100, do: {at, 1})
    assert %{index: 1, at: 705, frames: 3} = settled
  end

  test "starts a new shot when the page scrolls" do
    track = %{PointerTrack.empty() | scrolls: [[300, 0, 120]]}

    assert [{1, 5, 3}, {1, 305, 7} | _rest] =
             summary(plan(Fixtures.counter_recording(), track))
  end

  test "shows only the range asked for, holding its end" do
    schedule = plan(Fixtures.counter_recording(), PointerTrack.empty(), from: 1_500, to: 2_001)

    assert summary(schedule) == [{3, 1_500, 5}, {4, 2_000, 1}, {5, 2_100, 9}]
  end

  test "sizes the canvas to fit every viewport, rendering at a capped pixel ratio" do
    recording = Fixtures.counter_recording(clicks: 1)
    rotated = %Event{at: 500, type: :viewport, data: %{width: 844, height: 390, dpr: 3}}

    recording = %Recording{
      recording
      | client: %Client{viewport: %{width: 390, height: 844, dpr: 3}},
        events: List.insert_at(recording.events, 2, rotated)
    }

    schedule = plan(recording)

    assert schedule.canvas == %{width: 844, height: 844}
    assert schedule.dpr == 2

    assert Enum.map(schedule.shots, &{&1.index, &1.viewport}) == [
             {1, %{width: 390, height: 844}},
             {2, %{width: 844, height: 390}},
             {4, %{width: 844, height: 390}}
           ]
  end
end
