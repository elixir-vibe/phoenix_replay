defmodule PhoenixReplay.Recording.SummaryTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording.Summary
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

  test "lists distinct event names, sorted" do
    events =
      for name <- ~w(save inc save delete),
          do: %PhoenixReplay.Recording.Event{
            at: 0,
            type: :event,
            data: %{name: name, params: %{}}
          }

    assert Summary.event_names(events) == ~w(delete inc save)
  end
end
