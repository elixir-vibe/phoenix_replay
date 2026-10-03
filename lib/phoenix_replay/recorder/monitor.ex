defmodule PhoenixReplay.Recorder.Monitor do
  @moduledoc """
  Finalizes buffered sessions when their LiveView process exits.

  Each recorded process is monitored. On exit the buffered recording is
  either discarded (no user interaction) or handed to
  `PhoenixReplay.Recorder.Persister` in a supervised task. The buffer is
  closed once the task finishes, whether it saved the recording or gave up.

  On start the monitor re-attaches to every session already in
  `PhoenixReplay.Recorder.Buffer`, so a restart loses no recordings.
  """

  use GenServer

  require Logger

  alias PhoenixReplay.Recorder.{Buffer, Persister}
  alias PhoenixReplay.Recording.Timeline
  alias PhoenixReplay.{Recordings, Telemetry}

  @doc "Starts the monitor registered under its module name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Starts monitoring the session recorded by `pid`."
  @spec watch(pid(), PhoenixReplay.Recording.id()) :: :ok
  def watch(pid, id), do: GenServer.cast(__MODULE__, {:watch, pid, id})

  @impl true
  def init(_opts), do: {:ok, %{sessions: %{}, saves: %{}}, {:continue, :recover}}

  @impl true
  def handle_continue(:recover, state) do
    {:noreply,
     Enum.reduce(Buffer.sessions(), state, fn {id, pid}, acc -> watch(acc, pid, id) end)}
  end

  @impl true
  def handle_cast({:watch, pid, id}, state) do
    :ok = Recordings.broadcast_change()
    {:noreply, watch(state, pid, id)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case state do
      %{sessions: %{^ref => id}} -> {:noreply, finalize(state, ref, id)}
      %{saves: %{^ref => id}} -> {:noreply, save_crashed(state, ref, id, reason)}
    end
  end

  def handle_info({ref, _result}, %{saves: saves} = state) when is_map_key(saves, ref) do
    Process.demonitor(ref, [:flush])
    {id, saves} = Map.pop!(saves, ref)
    close(id)
    {:noreply, %{state | saves: saves}}
  end

  defp watch(%{sessions: sessions} = state, pid, id) do
    if id in Map.values(sessions) do
      state
    else
      %{state | sessions: Map.put(sessions, Process.monitor(pid), id)}
    end
  end

  defp finalize(state, ref, id) do
    state = %{state | sessions: Map.delete(state.sessions, ref)}

    with {:ok, recording} <- Buffer.fetch(id),
         {:ok, config} <- Buffer.config(id),
         true <- Timeline.interactive?(recording) do
      task =
        Task.Supervisor.async_nolink(PhoenixReplay.TaskSupervisor, Persister, :persist, [
          recording,
          config
        ])

      %{state | saves: Map.put(state.saves, task.ref, id)}
    else
      false ->
        Telemetry.discarded(id)
        close(id)
        state

      :error ->
        state
    end
  end

  defp save_crashed(state, ref, id, reason) do
    Logger.error(
      "PhoenixReplay: saving recording #{id} crashed: #{Exception.format_exit(reason)}"
    )

    Telemetry.failed(id, reason)
    close(id)
    %{state | saves: Map.delete(state.saves, ref)}
  end

  defp close(id) do
    :ok = Buffer.close(id)
    Recordings.broadcast_change()
  end
end
