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
             duration_ms: 1001,
             live?: false
           }

    assert Summary.new(recording, live?: true).live?
  end
end
