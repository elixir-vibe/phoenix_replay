defmodule PhoenixReplay.Recorder.FlushingTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Catalog, Config, Storage}
  alias PhoenixReplay.Session.{Buffer, Monitor, Recovery}
  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Test.{Fixtures, Sessions, Tasks}

  setup context do
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
    Sessions.setup_sessions(context)
  end

  # Runs one flush check and waits until the chunks it started are written.
  defp tick do
    send(Monitor, :tick)
    _state = :sys.get_state(Monitor)
    :ok = Tasks.await()
    _state = :sys.get_state(Monitor)
    :ok
  end

  defp click(view, times),
    do: for(_ <- 1..times, do: view |> element("button", "+") |> render_click())

  defp clicks(events), do: Enum.count(events, &(&1.type == :event))

  test "writes interactive sessions to storage in chunks while they run",
       %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/flushed/counter")
    click(view, 3)
    :ok = tick()

    assert Buffer.flushed?(id)
    assert Buffer.pending_count(id) == 0
    assert {:ok, partial} = Storage.fetch_partial(Fixtures.storage(), id)
    assert clicks(partial.events) == 3

    click(view, 2)
    assert {:ok, live} = Catalog.fetch(Config.load(), id)
    assert clicks(live.events) == 5

    assert Sessions.stop(sessions, view) == :persisted
    assert {:ok, saved} = Storage.fetch(Fixtures.storage(), id)
    assert clicks(saved.events) == 5
    assert saved.events |> Enum.map(& &1.at) |> then(&(&1 == Enum.sort(&1)))
    assert Storage.fetch_partial(Fixtures.storage(), id) == {:error, :not_found}
  end

  test "flushes on a session's own :flush while the global one is off", %{sessions: sessions} do
    # config/test.exs sets flush: false; the live session sets its own, and
    # the monitor's timer, not the test, has to notice it.
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/flushed/counter")
    click(view, 3)

    assert eventually(fn -> Buffer.flushed?(id) end, 3_000)
    assert Sessions.stop(sessions, view) == :persisted
  end

  defp eventually(check, timeout) do
    cond do
      check.() -> true
      timeout <= 0 -> false
      true -> Process.sleep(50) && eventually(check, timeout - 50)
    end
  end

  test "keeps every chunk when a session is flushed several times", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/flushed/counter")
    click(view, 1)
    :ok = tick()
    click(view, 2)
    :ok = tick()
    click(view, 1)

    assert Sessions.stop(sessions, view) == :persisted
    assert {:ok, saved} = Storage.fetch(Fixtures.storage(), id)
    assert [%Event{type: :mount} | _rest] = saved.events
    assert clicks(saved.events) == 4
  end

  test "writes nothing for sessions it would discard", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/flushed/counter")
    :ok = tick()

    refute Buffer.flushed?(id)
    assert Sessions.stop(sessions, view) == :discarded
    assert Storage.fetch_partial(Fixtures.storage(), id) == {:error, :not_found}
  end

  test "saves sessions a stopped node left in chunks, marked as interrupted" do
    config = Config.load()
    recording = Fixtures.counter_recording(id: "orphan")
    chunk = Enum.with_index(recording.events, fn event, seq -> {seq, event} end)
    :ok = Storage.append(config.storage, %{recording | events: []}, chunk)

    assert Recovery.run(config) == ["orphan"]
    assert {:ok, saved} = Storage.fetch(config.storage, "orphan")

    assert %Event{data: %{reason: "The node stopped" <> _}} =
             Enum.find(saved.events, &(&1.type == :exit))

    assert length(saved.events) == length(recording.events) + 1
    assert Storage.partials(config.storage) == []
  end
end
