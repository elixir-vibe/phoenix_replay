defmodule PhoenixReplay.Recording.SummaryTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording.{Event, Summary}
  alias PhoenixReplay.Test.Fixtures

  test "summarizes a recording" do
    recording = Fixtures.counter_recording(id: "abc", clicks: 1)

    assert Summary.new(recording) == %Summary{
             id: "abc",
             view: "PhoenixReplay.Test.Live.Counter",
             url: "http://localhost/counter",
             connected_at: recording.connected_at,
             event_count: 4,
             event_names: ["inc"],
             duration_ms: 1001,
             live?: false
           }

    assert Summary.new(recording, live?: true).live?
  end

  test "counts errors" do
    recording = Fixtures.counter_recording()
    exit = %Event{at: 9_000, type: :exit, data: %{reason: "boom"}}

    assert Summary.new(%{recording | events: [exit | recording.events]}).error_count == 1
  end

  test "lists distinct event names, sorted" do
    events =
      for name <- ~w(save inc save delete),
          do: %PhoenixReplay.Recording.Event{
            at: 0,
            type: :event,
            data: %{name: name, params: %{}}
          }

    assert Summary.totals(events).event_names == ~w(delete inc save)
    assert Summary.totals(events, Summary.totals(events)).event_count == 8
  end

  test "lists the names of the telemetry events that mark moments, but not of others" do
    telemetry = fn event, mark ->
      %Event{at: 0, type: :telemetry, data: %{event: event, measurements: %{}, mark: mark}}
    end

    events = [telemetry.([:shop, :checkout, :done], true), telemetry.([:repo, :query], false)]
    assert Summary.totals(events).event_names == ["shop.checkout.done"]
  end
end
