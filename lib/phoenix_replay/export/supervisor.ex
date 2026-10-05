defmodule PhoenixReplay.Export.Supervisor do
  @moduledoc """
  Supervises video export: `PhoenixReplay.Export.Runtime`, which starts
  the endpoint and Playwright on demand, `PhoenixReplay.Export.Server`,
  which queues jobs, and the task supervisor jobs run under.

  The tasks start after the server, so a server that restarts takes its
  running jobs with it rather than leaving them to report to nobody.
  """

  use Supervisor

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(_opts), do: Supervisor.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    Supervisor.init(
      [
        PhoenixReplay.Export.Runtime,
        PhoenixReplay.Export.Server,
        {Task.Supervisor, name: PhoenixReplay.Export.TaskSupervisor}
      ],
      strategy: :rest_for_one
    )
  end
end
