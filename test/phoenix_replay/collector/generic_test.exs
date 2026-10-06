defmodule PhoenixReplay.Collector.GenericTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Collector.Generic

  @event [:my_app, :search, :stop]

  test "keeps measurements and only the chosen metadata" do
    assert Generic.events(event: @event) == [@event]

    assert {:ok,
            %{
              summary: "my_app.search.stop",
              measurements: %{results: 3},
              metadata: %{query: "shoes"},
              error: nil
            }} =
             Generic.capture(@event, %{results: 3}, %{query: "shoes", socket: :big},
               event: @event,
               metadata: [:query]
             )
  end

  test "applies :keep and :summary to the metadata" do
    opts = [event: @event, keep: &(&1.query != ""), summary: &"search #{&1.query}"]

    assert {:ok, %{summary: "search shoes", metadata: %{}}} =
             Generic.capture(@event, %{}, %{query: "shoes"}, opts)

    assert Generic.capture(@event, %{}, %{query: ""}, opts) == :skip
  end

  test "marks moments with :mark" do
    assert {:ok, %{mark: false}} = Generic.capture(@event, %{}, %{}, event: @event)
    assert {:ok, %{mark: true}} = Generic.capture(@event, %{}, %{}, event: @event, mark: true)
  end

  test "records :exception events as errors" do
    event = [:my_app, :search, :exception]
    metadata = %{kind: :error, reason: %RuntimeError{message: "boom"}}

    assert {:ok, %{error: "** (RuntimeError) boom"}} =
             Generic.capture(event, %{}, metadata, event: event)
  end
end
