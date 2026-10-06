defmodule PhoenixReplay.Session.BufferTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Config
  alias PhoenixReplay.Session.Buffer
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

  test "summarizes buffered sessions", %{recording: %{id: id}} do
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

    assert {:ok, session, PhoenixReplay.Sanitizer.Default} =
             Buffer.attribute([spawn(fn -> :ok end), self()])

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

  test "flushing moves events out of the buffer into the session's totals",
       %{recording: %{id: id}} do
    :ok = Buffer.record(self(), :event, %{name: "save", params: %{}})
    :ok = Buffer.record(self(), :log, %{level: :error, message: "x", metadata: %{}})
    :ok = Buffer.record(self(), :info, %{tag: nil})

    refute Buffer.flushed?(id)
    assert [{0, %Event{type: :event}}, {1, %Event{}}, {2, %Event{}}] = Buffer.pending(id)
    assert [{2, %Event{type: :info}}] = Buffer.pending(id, 1)

    chunk = Enum.take(Buffer.pending(id), 2)
    :ok = Buffer.remove_flushed(id, chunk)

    assert Buffer.flushed?(id)
    assert Buffer.pending_count(id) == 1
    assert {:ok, %{events: [%Event{type: :info}]}} = Buffer.fetch(id)
    assert {:ok, %{events: []}} = Buffer.meta(id)

    assert %Summary{event_count: 3, event_names: ["save"], error_count: 1} =
             Enum.find(Buffer.summaries(), &(&1.id == id))

    # Totals are kept as events are written, so flushing them all changes nothing.
    :ok = Buffer.remove_flushed(id, Buffer.pending(id))
    assert {:ok, %{events: []}} = Buffer.fetch(id)

    assert %Summary{event_count: 3, event_names: ["save"], error_count: 1} =
             Enum.find(Buffer.summaries(), &(&1.id == id))
  end

  test "keeps the latest offset and distinct names, and leaves nothing on close",
       %{recording: %{id: id}} do
    :ok = Buffer.record(self(), :event, %{name: "save", params: %{}})
    Process.sleep(5)
    :ok = Buffer.record(self(), :event, %{name: "add", params: %{}})
    :ok = Buffer.record(self(), :event, %{name: "save", params: %{}})
    :ok = Buffer.record(self(), :pointer, %{span: 0, moves: [], presses: [], scrolls: []})

    {:ok, %{events: events}} = Buffer.fetch(id)
    summary = Enum.find(Buffer.summaries(), &(&1.id == id))

    assert summary.event_names == ["add", "save"]
    assert summary.event_count == 3
    assert summary.duration_ms == events |> Enum.map(& &1.at) |> Enum.max()
    assert summary.duration_ms >= 5

    # A session row whose key sorts before the others does not hide the
    # latest event.
    :ets.insert(Buffer, {{id, :aardvark}, nil})
    assert Enum.find(Buffer.summaries(), &(&1.id == id)).duration_ms == summary.duration_ms
    :ets.delete(Buffer, {id, :aardvark})

    :ok = Buffer.close(id)
    assert :ets.match(Buffer, {{:event_name, id, :_}}) == []
    assert :ets.match(Buffer, {{id, :_}, :_}) == []
  end

  test "keeps the draw made when the session opened" do
    recording = %{Fixtures.counter_recording() | events: []}
    :ok = Buffer.open(recording, self(), Config.new([]), 0.25)
    on_exit(fn -> Buffer.close(recording.id) end)

    assert Buffer.draw(recording.id) == {:ok, 0.25}
    assert Buffer.draw("missing") == :error
  end

  test "close removes the session and its events", %{recording: %{id: id}} do
    Buffer.append(id, 0, %Event{at: 0, type: :mount, data: %{assigns: %{}}})
    assert :ok = Buffer.close(id)
    assert Buffer.fetch(id) == :error
    assert :ets.match(Buffer, {{id, :_}, :_}) == []
  end

  test "counts large binaries in memory, until they are flushed", %{recording: %{id: id}} do
    message = String.duplicate("x", 2_000_000)
    :ok = Buffer.record(self(), :log, %{level: :info, message: message, metadata: %{}})

    # ETS alone counts the binary by reference, a few bytes. The total
    # covers every session, and other tests' sessions come and go, so it is
    # compared with the binary, not with a reading taken before it.
    holding = Buffer.memory()
    assert holding >= 2_000_000

    :ok = Buffer.remove_flushed(id, Buffer.pending(id))
    assert holding - Buffer.memory() >= 1_900_000
  end

  test "a collector writing as its session closes leaves nothing behind", %{
    recording: %{id: id}
  } do
    {:ok, session, _sanitizer} = Buffer.attribute([self()])
    :ok = Buffer.close(id)

    assert :ok =
             Buffer.collect(
               session,
               :log,
               %{level: :info, message: "late", metadata: %{}},
               "logs",
               10
             )

    assert :ets.match(Buffer, {{:collected, id, :_}, :_, :_}) == []
    assert :ets.match(Buffer, {{id, :_}, :_}) == []
  end

  test "leaves sessions being saved out of the ones a restarted monitor watches", %{
    recording: %{id: id}
  } do
    assert {id, self()} in Buffer.sessions()
    :ok = Buffer.mark_saving(id)
    refute {id, self()} in Buffer.sessions()
  end
end
