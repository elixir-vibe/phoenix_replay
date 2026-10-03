defmodule PhoenixReplay.Application do
  @moduledoc """
  Starts PhoenixReplay's supervision tree.

  The recording buffer table is created here rather than in a worker, so
  in-progress recordings survive any worker restart.
  """

  use Application

  @impl true
  def start(_type, _args) do
    :ok = PhoenixReplay.Recorder.Buffer.create_table()
    :ok = PhoenixReplay.Recorder.Components.attach()

    children = [
      {Phoenix.PubSub, name: PhoenixReplay.PubSub},
      {Task.Supervisor, name: PhoenixReplay.TaskSupervisor},
      PhoenixReplay.Recorder.Monitor,
      PhoenixReplay.Retention
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: PhoenixReplay.Supervisor)
  end
end
