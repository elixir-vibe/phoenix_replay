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

  test "counts the marks reached, by name, apart from event names" do
    telemetry = fn event, mark ->
      %Event{at: 0, type: :telemetry, data: %{event: event, measurements: %{}, mark: mark}}
    end

    events = [
      telemetry.([:shop, :checkout, :done], true),
      telemetry.([:shop, :checkout, :done], true),
      telemetry.([:shop, :signup], "Signed up"),
      telemetry.([:repo, :query], false)
    ]

    assert %{event_names: [], marks: %{"shop.checkout.done" => 2, "Signed up" => 1}} =
             Summary.totals(events)
  end

  test "reads where a visit came from as an earlier version saved it" do
    old = &Summary.upgrade(%Summary{id: "a", view: "V", connected_at: 0, source: &1})

    assert %{source: "google", medium: "cpc", campaign: "spring"} = old.("google / cpc / spring")
    assert %{source: "google", medium: "cpc", campaign: nil} = old.("google / cpc")
    assert %{source: "news.ycombinator.com", medium: "referral"} = old.("news.ycombinator.com")
    assert %{source: "hn", medium: "(none)"} = old.("hn")
    assert %{source: nil, medium: nil} = old.(nil)

    assert %{device_type: "phone"} =
             Summary.upgrade(%Summary{
               id: "a",
               view: "V",
               connected_at: 0,
               viewport: %{width: 390, height: 844, dpr: 3}
             })
  end
end
