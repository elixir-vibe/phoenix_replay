defmodule PhoenixReplay.Capture.HandlersTest do
  use ExUnit.Case, async: false

  alias PhoenixReplay.Capture.{Handlers, LiveComponents}

  defp attached do
    for %{id: LiveComponents} <- :telemetry.list_handlers([:phoenix, :live_component]),
        do: LiveComponents
  end

  test "detaches handlers when stopped and attaches them when started" do
    :ok = Supervisor.terminate_child(PhoenixReplay.Supervisor, Handlers)
    assert attached() == []

    {:ok, _pid} = Supervisor.restart_child(PhoenixReplay.Supervisor, Handlers)
    assert attached() != []
  end

  test "attaches each handler once after being killed" do
    before = length(attached())
    pid = Process.whereis(Handlers)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    # The supervisor restarts the child while handling the exit, before this
    # call returns. A child whose init failed would be :restarting instead.
    children = Supervisor.which_children(PhoenixReplay.Supervisor)
    assert {Handlers, restarted, :worker, _modules} = List.keyfind(children, Handlers, 0)
    assert is_pid(restarted) and restarted != pid
    assert length(attached()) == before
  end
end
