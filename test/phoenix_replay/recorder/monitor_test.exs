defmodule PhoenixReplay.Recorder.MonitorTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Config, Storage}
  alias PhoenixReplay.Recorder.{Buffer, Monitor}
  alias PhoenixReplay.Test.{Assertions, Fixtures, TelemetryHandler}

  @endpoint PhoenixReplay.Test.Endpoint

  setup context do
    TelemetryHandler.attach(context.test)
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
  end

  defp buffer(recording, pid, config) do
    :ok = Buffer.open(recording, pid, config)

    recording.events
    |> Enum.with_index()
    |> Enum.each(fn {event, seq} -> Buffer.append(recording.id, seq, event) end)
  end

  test "discards sessions without interaction" do
    {:ok, view, _html} = live(build_conn(), "/counter")
    id = :sys.get_state(view.pid).socket.private.phoenix_replay.id
    GenServer.stop(view.pid)

    assert_receive {:telemetry, :discarded, %{id: ^id}}
    assert Buffer.fetch(id) == :error
    assert Storage.fetch(Fixtures.storage(), id) == {:error, :not_found}
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
    Assertions.eventually(fn -> if Buffer.fetch(id) == :error, do: {:ok, :closed} end)
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
end
