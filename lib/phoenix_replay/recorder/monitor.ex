defmodule PhoenixReplay.Recorder.Monitor do
  @moduledoc """
  Finalizes buffered sessions when their LiveView process exits.

  Each recorded process is monitored. When it exits abnormally, its exit
  reason is recorded as an `:exit` event. The buffered recording is then
  either discarded or handed to `PhoenixReplay.Recorder.Persister` in a
  supervised task, as `PhoenixReplay.Recording.Keep` decides. The buffer is
  closed once the task finishes, whether it saved the recording or gave up.

  Each outcome emits its `PhoenixReplay.Telemetry` event after the buffer is
  closed, so a handler observes the finished state.

  On start the monitor re-attaches to every session already in
  `PhoenixReplay.Recorder.Buffer`, so a restart loses no recordings.
  """

  use GenServer

  require Logger

  alias PhoenixReplay.Recorder.{Buffer, Persister}
  alias PhoenixReplay.Recording.Keep
  alias PhoenixReplay.{Recordings, Sanitizer, Telemetry}

  @max_reason 4_000

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
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case state do
      %{sessions: %{^ref => id}} -> {:noreply, finalize(state, ref, id, pid, reason)}
      %{saves: %{^ref => recording}} -> {:noreply, save_crashed(state, ref, recording, reason)}
      %{} -> {:noreply, state}
    end
  end

  def handle_info({ref, result}, %{saves: saves} = state) when is_map_key(saves, ref) do
    Process.demonitor(ref, [:flush])
    {recording, saves} = Map.pop!(saves, ref)
    close(recording.id)

    case result do
      :ok -> Telemetry.persisted(recording)
      {:error, reason} -> Telemetry.failed(recording.id, reason)
    end

    {:noreply, %{state | saves: saves}}
  end

  defp watch(%{sessions: sessions} = state, pid, id) do
    if id in Map.values(sessions) do
      state
    else
      %{state | sessions: Map.put(sessions, Process.monitor(pid), id)}
    end
  end

  defp finalize(state, ref, id, pid, reason) do
    state = %{state | sessions: Map.delete(state.sessions, ref)}
    record_exit(pid, reason)

    with {:ok, recording} <- Buffer.fetch(id),
         {:ok, config} <- Buffer.config(id),
         :keep <- Keep.decide(recording, config.keep) do
      task =
        Task.Supervisor.async_nolink(PhoenixReplay.TaskSupervisor, Persister, :persist, [
          recording,
          config
        ])

      %{state | saves: Map.put(state.saves, task.ref, recording)}
    else
      {:discard, reason} ->
        close(id)
        Telemetry.discarded(id, reason)
        state

      :error ->
        state
    end
  end

  defp record_exit(_pid, reason) when reason in [:normal, :shutdown, :noproc], do: :ok
  defp record_exit(_pid, {:shutdown, _reason}), do: :ok

  defp record_exit(pid, reason) do
    with {:ok, session, config} <- Buffer.attribute([pid]) do
      text = reason |> Exception.format_exit() |> String.slice(0, @max_reason)
      Buffer.collect(session, :exit, %{reason: Sanitizer.redact(text, config.redact)}, "exit", 1)
    end
  end

  defp save_crashed(state, ref, recording, reason) do
    Logger.error(
      "PhoenixReplay: saving recording #{recording.id} crashed: #{Exception.format_exit(reason)}"
    )

    close(recording.id)
    Telemetry.failed(recording.id, reason)
    %{state | saves: Map.delete(state.saves, ref)}
  end

  defp close(id) do
    :ok = Buffer.close(id)
    Recordings.broadcast_change()
  end
end
