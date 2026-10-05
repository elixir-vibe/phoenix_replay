defmodule PhoenixReplay.Recording.StateTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Event, Keep, State, Summary, Timeline}

  defp recording(events), do: %Recording{id: "r", view: V, connected_at: 0, events: events}

  defp batch(at, span, entries),
    do: %Event{at: at, type: :state, data: %{span: span, entries: entries}}

  @mount %Event{at: 0, type: :mount, data: %{assigns: %{}}}
  @click %Event{at: 250, type: :event, data: %{name: "save", params: %{}}}
  @render %Event{at: 251, type: :render, data: %{assigns: %{saved: true}}}

  test "spreads batches into an event per entry, keeping the other events' order" do
    spread =
      State.spread(
        recording([
          @mount,
          @click,
          @render,
          batch(300, 200, [[0, "a", %{"x" => 1}], [200, "a", %{"y" => 2}]])
        ])
      )

    assert [
             @mount,
             %Event{at: 100, type: :state, data: %{key: "a", changes: %{"x" => 1}}},
             @click,
             @render,
             %Event{at: 300, type: :state, data: %{key: "a", changes: %{"y" => 2}}}
           ] = spread.events

    assert State.spread(spread) == spread
  end

  test "folds state into the reserved assign, through mounts and back" do
    recording =
      State.spread(
        recording([
          @mount,
          batch(10, 0, [[0, "a", %{"x" => 1, "y" => 1}]]),
          %Event{at: 20, type: :mount, data: %{assigns: %{n: 1}}},
          batch(30, 0, [[0, "a", %{"y" => 2}], [0, "b", %{"z" => 3}]])
        ])
      )

    assert Timeline.at(recording, 0).assigns == %{phoenix_replay_state: %{}}

    assert Timeline.at(recording, 2).assigns.phoenix_replay_state == %{
             "a" => %{"x" => 1, "y" => 1}
           }

    last = Timeline.at(recording, 4)
    assert last.assigns.n == 1

    assert last.assigns.phoenix_replay_state == %{
             "a" => %{"x" => 1, "y" => 2},
             "b" => %{"z" => 3}
           }

    assert Timeline.seek(last, 1) == Timeline.at(recording, 1)
  end

  test "counts as interaction once a key changes, not when first reported" do
    keep = %{rate: 1.0, errors: false, slower_than: nil}
    first = recording([@mount, batch(10, 0, [[0, "a", %{"x" => 1}], [0, "b", %{}]])])

    again =
      recording([
        @mount,
        batch(10, 0, [[0, "a", %{"x" => 1}]]),
        batch(20, 0, [[0, "a", %{"x" => 2}]])
      ])

    assert Keep.decide(first, keep, 0.5) == {:discard, :not_interactive}
    assert Keep.decide(again, keep, 0.5) == :keep
  end

  test "is not counted as events in summaries" do
    assert Summary.totals([@mount, batch(10, 0, [[0, "a", %{}]])]).event_count == 1
  end
end
