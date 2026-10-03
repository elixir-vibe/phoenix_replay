defmodule PhoenixReplay.Application do
  @moduledoc """
  Starts PhoenixReplay's supervision tree.

  The recording buffer table is created here rather than in a worker, so
  in-progress recordings survive any worker restart. Telemetry and log
  handlers are attached here too, from the `:collect` and `:logs`
  configuration, so changing them takes an application restart.
  """

  use Application

  @impl true
  def start(_type, _args) do
    config = PhoenixReplay.Config.load()
    :ok = PhoenixReplay.Recorder.Buffer.create_table()
    :ok = PhoenixReplay.Recorder.Components.attach()
    :ok = PhoenixReplay.Recorder.Collectors.attach(config)
    :ok = PhoenixReplay.Recorder.Logs.attach(config)

    children = [
      {Phoenix.PubSub, name: PhoenixReplay.PubSub},
      {Task.Supervisor, name: PhoenixReplay.TaskSupervisor},
      PhoenixReplay.Recorder.Monitor,
      PhoenixReplay.Retention
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: PhoenixReplay.Supervisor)
  end
end
