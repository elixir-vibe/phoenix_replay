defmodule PhoenixReplay.Application do
  @moduledoc """
  Starts PhoenixReplay's supervision tree.

  The recording buffer table is created here rather than in a worker, so
  in-progress recordings survive any worker restart. The storage backend's
  own process, if it has one, starts first; see
  `c:PhoenixReplay.Storage.child_spec/1`. Changing `:storage` to a backend
  with a process takes an application restart.
  `PhoenixReplay.Export.Supervisor` runs video exports, starting what
  they need only with the first one.
  `PhoenixReplay.Capture.Handlers` attaches the telemetry and log handlers
  from the `:collect` and `:logs` configuration, so changing them takes an
  application restart.
  """

  use Application

  @impl true
  def start(_type, _args) do
    :ok = PhoenixReplay.Session.Buffer.create_table()
    config = PhoenixReplay.Config.load()

    children =
      PhoenixReplay.Storage.children(config.storage) ++
        [
          {Phoenix.PubSub, name: PhoenixReplay.PubSub},
          {Task.Supervisor, name: PhoenixReplay.TaskSupervisor},
          PhoenixReplay.Export.Supervisor,
          {PhoenixReplay.Capture.Handlers, config},
          PhoenixReplay.Session.Monitor,
          {Task, &PhoenixReplay.Session.Recovery.run/0},
          PhoenixReplay.Storage.Retention
        ]

    Supervisor.start_link(children, strategy: :one_for_one, name: PhoenixReplay.Supervisor)
  end
end
