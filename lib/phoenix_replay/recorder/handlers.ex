defmodule PhoenixReplay.Recorder.Handlers do
  @moduledoc """
  Owns the telemetry and `:logger` handlers that record sessions.

  Handlers are global and outlive the process that attaches them, so this
  process ties their lifetime to the supervision tree: it attaches
  `PhoenixReplay.Recorder.Components`, the configured
  `PhoenixReplay.Recorder.Collectors` and `PhoenixReplay.Recorder.Logs`
  when it starts, and detaches them when it stops. It traps exits so it
  detaches them on shutdown, and detaches leftovers before attaching, so a
  restart after it was killed attaches each handler once.

  The handlers run in the processes that emit events, not in this one, so
  recording never waits on it.
  """

  use GenServer

  alias PhoenixReplay.Config
  alias PhoenixReplay.Recorder.{Collectors, Components, Logs}

  @doc "Starts the handler owner registered under its module name."
  @spec start_link(Config.t()) :: GenServer.on_start()
  def start_link(%Config{} = config),
    do: GenServer.start_link(__MODULE__, config, name: __MODULE__)

  @impl true
  def init(config) do
    Process.flag(:trap_exit, true)
    detach()
    :ok = Components.attach()
    :ok = Collectors.attach(config)
    :ok = Logs.attach(config)
    {:ok, nil}
  end

  @impl true
  def terminate(_reason, nil), do: detach()

  defp detach do
    :ok = Components.detach()
    :ok = Collectors.detach()
    :ok = Logs.detach()
  end
end
