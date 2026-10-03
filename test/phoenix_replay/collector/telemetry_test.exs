defmodule PhoenixReplay.Collector.TelemetryTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Collector.Telemetry

  @event [:my_app, :search, :stop]

  test "keeps measurements and only the chosen metadata" do
    assert Telemetry.events(event: @event) == [@event]

    assert {:ok,
            %{
              summary: "my_app.search.stop",
              measurements: %{results: 3},
              metadata: %{query: "shoes"},
              error: nil
            }} =
             Telemetry.capture(@event, %{results: 3}, %{query: "shoes", socket: :big},
               event: @event,
               metadata: [:query]
             )
  end

  test "applies :keep and :summary to the metadata" do
    opts = [event: @event, keep: &(&1.query != ""), summary: &"search #{&1.query}"]

    assert {:ok, %{summary: "search shoes", metadata: %{}}} =
             Telemetry.capture(@event, %{}, %{query: "shoes"}, opts)

    assert Telemetry.capture(@event, %{}, %{query: ""}, opts) == :skip
  end

  test "records :exception events as errors" do
    event = [:my_app, :search, :exception]
    metadata = %{kind: :error, reason: %RuntimeError{message: "boom"}}

    assert {:ok, %{error: "** (RuntimeError) boom"}} =
             Telemetry.capture(event, %{}, metadata, event: event)
  end
end
