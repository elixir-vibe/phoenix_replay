defmodule PhoenixReplay.Test.Tasks do
  @moduledoc "Waits for PhoenixReplay's supervised tasks."

  import ExUnit.Assertions

  @doc "Returns the tasks currently running under `PhoenixReplay.TaskSupervisor`."
  @spec running() :: [pid()]
  def running, do: Task.Supervisor.children(PhoenixReplay.TaskSupervisor)

  @doc "Waits until every task running now has exited."
  @spec await() :: :ok
  def await do
    for pid <- running() do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000
    end

    :ok
  end
end
