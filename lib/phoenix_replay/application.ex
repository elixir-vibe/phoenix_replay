defmodule PhoenixReplay.Application do
  @moduledoc """
  Starts PhoenixReplay's supervision tree.

  The recording buffer table is created here rather than in a worker, so
  in-progress recordings survive any worker restart.
  `PhoenixReplay.Capture.Handlers` attaches the telemetry and log handlers
  from the `:collect` and `:logs` configuration, so changing them takes an
  application restart.
  """

  use Application

  @impl true
  def start(_type, _args) do
    :ok = PhoenixReplay.Storage.File.remember_root()
    :ok = PhoenixReplay.Session.Buffer.create_table()
    :ok = PhoenixReplay.Storage.File.create_index()

    children = [
      {Phoenix.PubSub, name: PhoenixReplay.PubSub},
      {Task.Supervisor, name: PhoenixReplay.TaskSupervisor},
      {PhoenixReplay.Capture.Handlers, PhoenixReplay.Config.load()},
      PhoenixReplay.Session.Monitor,
      {Task, &PhoenixReplay.Session.Recovery.run/0},
      PhoenixReplay.Recordings.Retention
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: PhoenixReplay.Supervisor)
  end
end
