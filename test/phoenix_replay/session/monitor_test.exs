defmodule PhoenixReplay.Session.MonitorTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Config, Storage}
  alias PhoenixReplay.Session.{Buffer, Monitor}
  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Test.{Fixtures, Sessions, TelemetryHandler}

  setup context do
    TelemetryHandler.attach(context.test)
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
    Sessions.setup_sessions(context)
  end

  defp buffer(recording, pid, config) do
    :ok = Buffer.open(recording, pid, config)

    recording.events
    |> Enum.with_index()
    |> Enum.each(fn {event, seq} -> Buffer.append(recording.id, seq, event) end)
  end

  test "discards sessions without interaction", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/counter")

    assert Sessions.stop(sessions, view) == :discarded
    assert_received {:telemetry, :discarded, %{id: ^id, reason: :not_interactive}}
    assert Buffer.fetch(id) == :error
    assert Storage.fetch(Fixtures.storage(), id) == {:error, :not_found}
  end

  test "discards interactive sessions that keep: [rate: ...] does not sample",
       %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/tail/counter")
    view |> element("button", "+") |> render_click()

    assert Sessions.stop(sessions, view) == :discarded
    assert_received {:telemetry, :discarded, %{id: ^id, reason: :not_sampled}}
  end

  test "records an abnormal exit and keeps the session for keep: [errors: true]",
       %{sessions: sessions} do
    Process.flag(:trap_exit, true)
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/tail/counter")
    Process.exit(view.pid, {:boom, :test})

    assert Sessions.await(sessions, id) == :persisted
    {:ok, recording} = Storage.fetch(Fixtures.storage(), id)
    assert %Event{data: %{reason: reason}} = Enum.find(recording.events, &(&1.type == :exit))
    assert reason =~ "boom"
  end

  test "drops the buffer after persistence gives up" do
    recording = Fixtures.counter_recording()
    pid = spawn(fn -> receive do: (:stop -> :ok) end)

    config =
      Config.new(
        storage: {PhoenixReplay.Test.FailingStorage, notify: self()},
        persist: [attempts: 2, backoff: 0]
      )

    buffer(recording, pid, config)
    Monitor.watch(pid, recording.id)
    send(pid, :stop)

    id = recording.id
    assert_receive {:save_attempt, ^id}
    assert_receive {:save_attempt, ^id}
    assert_receive {:telemetry, :failed, %{id: ^id, reason: :unavailable}}
    assert Buffer.fetch(id) == :error
  end

  test "recovers buffered sessions after a restart" do
    recording = Fixtures.counter_recording()
    pid = spawn(fn -> :ok end)
    buffer(recording, pid, Config.load())

    :ok = Supervisor.terminate_child(PhoenixReplay.Supervisor, Monitor)
    {:ok, _pid} = Supervisor.restart_child(PhoenixReplay.Supervisor, Monitor)

    id = recording.id
    assert_receive {:telemetry, :persisted, %{id: ^id}}
    assert Storage.fetch(Fixtures.storage(), id) == {:ok, recording}
  end

  test "waits for saves and flushes in flight when it stops" do
    test = self()

    task =
      Task.Supervisor.async_nolink(PhoenixReplay.TaskSupervisor, fn ->
        # Long enough that returning without waiting would miss it.
        Process.sleep(50)
        send(test, :finished)
        :ok
      end)

    state = %{tasks: %{task.ref => %{kind: :save, id: "x", task: task}}}

    assert Monitor.terminate(:shutdown, state) == :ok
    assert_received :finished
  end
end
