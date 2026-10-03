defmodule PhoenixReplay.Recorder.BufferTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Config
  alias PhoenixReplay.Recorder.Buffer
  alias PhoenixReplay.Recording.{Event, Summary}
  alias PhoenixReplay.Test.Fixtures

  setup do
    recording = %{Fixtures.counter_recording() | events: []}
    :ok = Buffer.open(recording, self(), Config.new([]))
    on_exit(fn -> Buffer.close(recording.id) end)
    %{recording: recording}
  end

  test "appends events in sequence order", %{recording: %{id: id}} do
    for seq <- [2, 0, 1],
        do: Buffer.append(id, seq, %Event{at: seq * 10, type: :info, data: %{tag: nil}})

    assert {:ok, %{events: events}} = Buffer.fetch(id)
    assert Enum.map(events, & &1.at) == [0, 10, 20]
    assert {:ok, %Config{}} = Buffer.config(id)
    assert {id, self()} in Buffer.sessions()
  end

  test "summarizes sessions without decoding events", %{recording: %{id: id}} do
    Buffer.append(id, 0, %Event{at: 0, type: :mount, data: %{assigns: %{}}})
    Buffer.append(id, 1, %Event{at: 250, type: :info, data: %{tag: nil}})
    Buffer.append(id, 2, %Event{at: 260, type: :event, data: %{name: "save", params: %{}}})
    Buffer.append(id, 3, %Event{at: 270, type: :event, data: %{name: "save", params: %{}}})

    assert %Summary{event_count: 4, event_names: ["save"], duration_ms: 270, live?: true} =
             Enum.find(Buffer.summaries(), &(&1.id == id))
  end

  test "records LiveView events up to :max_events, apart from collected ones" do
    recording = %{Fixtures.counter_recording() | events: []}
    :ok = Buffer.open(recording, self(), Config.new(max_events: 1))
    on_exit(fn -> Buffer.close(recording.id) end)

    assert {:ok, session, %Config{}} = Buffer.attribute([spawn(fn -> :ok end), self()])
    assert Buffer.record(self(), :info, %{tag: nil}) == :ok
    assert Buffer.record(self(), :info, %{tag: nil}) == :full
    assert Buffer.collect(session, :log, %{level: :info}, "log", 1) == :ok
    assert Buffer.collect(session, :log, %{level: :info}, "log", 1) == :dropped
    assert Buffer.collect(session, :log, %{level: :info}, "log", 1) == :dropped

    assert {:ok, %{events: [%Event{type: :info}, %Event{type: :log}], dropped: %{"log" => 2}}} =
             Buffer.fetch(recording.id)
  end

  test "finds no session for processes that record none" do
    assert Buffer.attribute([spawn(fn -> :ok end)]) == :error
    assert Buffer.attribute([]) == :error
  end

  test "counts errors in summaries", %{recording: %{id: id}} do
    Buffer.append(id, 0, %Event{at: 0, type: :log, data: %{level: :error, message: "x"}})
    Buffer.append(id, 1, %Event{at: 1, type: :log, data: %{level: :info, message: "x"}})
    Buffer.append(id, 2, %Event{at: 2, type: :exit, data: %{reason: "boom"}})

    assert %Summary{error_count: 2} = Enum.find(Buffer.summaries(), &(&1.id == id))
    assert Buffer.memory() > 0
  end

  test "close removes the session and its events", %{recording: %{id: id}} do
    Buffer.append(id, 0, %Event{at: 0, type: :mount, data: %{assigns: %{}}})
    assert :ok = Buffer.close(id)
    assert Buffer.fetch(id) == :error
    assert :ets.match(Buffer, {{id, :_}, :_}) == []
  end
end
