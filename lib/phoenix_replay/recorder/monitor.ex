defmodule PhoenixReplay.Recorder.Monitor do
  @moduledoc """
  Follows each recorded session from its first event to storage.

  Each recorded process is monitored. While it runs, the monitor checks
  its sessions periodically and writes a session's buffered events to
  storage as a chunk, with `PhoenixReplay.Recorder.Flusher`, once
  `PhoenixReplay.Recording.Keep` decides to keep it and `:flush` says a
  chunk is due. Keeping is decided from the events seen so far, which are
  observed incrementally, and never turns back, so nothing is written that
  would be discarded later.

  When the process exits abnormally, its exit reason is recorded as an
  `:exit` event. The session is then discarded, or saved by
  `PhoenixReplay.Recorder.Persister` in a supervised task, after any flush
  in flight. The buffer is closed once the task finishes, whether it saved
  the recording or gave up. Each outcome emits its `PhoenixReplay.Telemetry`
  event after the buffer is closed, so a handler observes the finished
  state.

  On shutdown the monitor waits for saves and flushes in flight. On start
  it re-attaches to every session already in
  `PhoenixReplay.Recorder.Buffer`, so a restart loses no recordings.
  """

  use GenServer

  require Logger

  alias PhoenixReplay.{Config, Recordings, Storage, Telemetry}
  alias PhoenixReplay.Recorder.{Buffer, Flusher, Persister}
  alias PhoenixReplay.Recording.Keep

  @max_reason 4_000
  @max_tick 1_000
  @drain_timeout 25_000

  @doc "Starts the monitor registered under its module name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc false
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, shutdown: @drain_timeout + 5_000}
  end

  @doc "Starts monitoring the session recorded by `pid`."
  @spec watch(pid(), PhoenixReplay.Recording.id()) :: :ok
  def watch(pid, id), do: GenServer.cast(__MODULE__, {:watch, pid, id})

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    state = %{sessions: %{}, tracks: %{}, tasks: %{}, tick: tick(Config.load().flush)}
    {:ok, schedule_tick(state), {:continue, :recover}}
  end

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
  def handle_info(:tick, state) do
    state = schedule_tick(state)
    {:noreply, Enum.reduce(state.tracks, state, fn {id, track}, acc -> check(acc, id, track) end)}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case state do
      %{sessions: %{^ref => id}} -> {:noreply, ended(state, ref, id, pid, reason)}
      %{tasks: %{^ref => task}} -> {:noreply, task_crashed(state, ref, task, reason)}
      %{} -> {:noreply, state}
    end
  end

  def handle_info({ref, result}, %{tasks: tasks} = state) when is_map_key(tasks, ref) do
    Process.demonitor(ref, [:flush])
    {task, tasks} = Map.pop!(tasks, ref)
    {:noreply, completed(%{state | tasks: tasks}, task, result)}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    state.tasks |> Map.values() |> Enum.map(& &1.task) |> Task.yield_many(@drain_timeout)
    :ok
  end

  defp watch(%{tracks: tracks} = state, _pid, id) when is_map_key(tracks, id), do: state

  defp watch(state, pid, id) do
    track = %{
      observation: Keep.new(),
      checked: -1,
      committed?: Buffer.flushed?(id),
      flushed_at: now(),
      flushing?: false,
      ended?: false
    }

    %{
      state
      | sessions: Map.put(state.sessions, Process.monitor(pid), id),
        tracks: Map.put(state.tracks, id, track)
    }
  end

  ## Flushing

  defp check(state, _id, %{flushing?: true}), do: state
  defp check(state, _id, %{ended?: true}), do: state

  defp check(state, id, track) do
    with {:ok, config} <- Buffer.config(id),
         %{} = flush <- config.flush,
         true <- Storage.chunked?(config.storage),
         true <- due?(Buffer.pending_count(id), flush, track) do
      track = observe(track, id, config)
      if track.committed?, do: start_flush(state, id, track), else: put_track(state, id, track)
    else
      _not_due -> state
    end
  end

  defp due?(0, _flush, _track), do: false

  defp due?(pending, flush, track),
    do: pending >= flush.events or now() - track.flushed_at >= flush.interval

  defp observe(%{committed?: true} = track, _id, _config), do: track

  defp observe(track, id, config) do
    events = Buffer.pending(id, track.checked)
    observation = Keep.observe(track.observation, Enum.map(events, &elem(&1, 1)), config.keep)
    {:ok, draw} = Buffer.draw(id)

    %{
      track
      | observation: observation,
        checked: Enum.reduce(events, track.checked, fn {seq, _event}, acc -> max(seq, acc) end),
        committed?: Keep.decision(observation, config.keep, draw) == :keep
    }
  end

  defp start_flush(state, id, track) do
    task = Task.Supervisor.async_nolink(PhoenixReplay.TaskSupervisor, Flusher, :flush, [id])

    %{
      state
      | tasks: Map.put(state.tasks, task.ref, %{kind: :flush, id: id, task: task}),
        tracks: Map.put(state.tracks, id, %{track | flushing?: true})
    }
  end

  ## Finishing

  defp ended(state, ref, id, pid, reason) do
    state = %{state | sessions: Map.delete(state.sessions, ref)}
    record_exit(pid, reason)

    case state.tracks do
      %{^id => %{flushing?: true} = track} -> put_track(state, id, %{track | ended?: true})
      %{} -> finalize(state, id)
    end
  end

  defp finalize(state, id) do
    state = %{state | tracks: Map.delete(state.tracks, id)}

    with {:ok, recording} <- Buffer.fetch(id),
         {:ok, config} <- Buffer.config(id),
         :keep <- keep(id, recording, config) do
      task =
        Task.Supervisor.async_nolink(PhoenixReplay.TaskSupervisor, Persister, :persist, [
          recording,
          config
        ])

      %{state | tasks: Map.put(state.tasks, task.ref, %{kind: :save, id: id, task: task})}
    else
      {:discard, reason} ->
        close(id)
        Telemetry.discarded(id, reason)
        state

      :error ->
        state
    end
  end

  # A session that flushed chunks was kept, and keeping never turns back.
  defp keep(id, recording, config) do
    if Buffer.flushed?(id) do
      :keep
    else
      {:ok, draw} = Buffer.draw(id)
      Keep.decide(recording, config.keep, draw)
    end
  end

  defp completed(state, %{kind: :flush, id: id}, result) do
    if result != :ok do
      Logger.error("PhoenixReplay: flushing recording #{id} failed: #{inspect(result)}")
    end

    flushed(state, id)
  end

  defp completed(state, %{kind: :save, id: id}, result) do
    close(id)

    case result do
      {:ok, recording} -> Telemetry.persisted(recording)
      {:error, reason} -> Telemetry.failed(id, reason)
    end

    state
  end

  defp task_crashed(state, ref, %{kind: kind, id: id}, reason) do
    Logger.error(
      "PhoenixReplay: #{kind} of recording #{id} crashed: #{Exception.format_exit(reason)}"
    )

    state = %{state | tasks: Map.delete(state.tasks, ref)}

    case kind do
      :flush ->
        flushed(state, id)

      :save ->
        close(id)
        Telemetry.failed(id, reason)
        state
    end
  end

  defp flushed(state, id) do
    case state.tracks do
      %{^id => %{ended?: true}} ->
        finalize(state, id)

      %{^id => track} ->
        put_track(state, id, %{track | flushing?: false, flushed_at: now()})

      %{} ->
        state
    end
  end

  defp record_exit(_pid, reason) when reason in [:normal, :shutdown, :noproc], do: :ok
  defp record_exit(_pid, {:shutdown, _reason}), do: :ok

  defp record_exit(pid, reason) do
    with {:ok, session, _config} <- Buffer.attribute([pid]) do
      text = reason |> Exception.format_exit() |> String.slice(0, @max_reason)
      Buffer.collect(session, :exit, %{reason: text}, "exit", 1)
    end
  end

  defp put_track(state, id, track), do: %{state | tracks: Map.put(state.tracks, id, track)}

  defp close(id) do
    :ok = Buffer.close(id)
    Recordings.broadcast_change()
  end

  defp tick(nil), do: nil
  defp tick(%{interval: interval}), do: min(interval, @max_tick)

  defp schedule_tick(%{tick: nil} = state), do: state

  defp schedule_tick(%{tick: tick} = state) do
    Process.send_after(self(), :tick, tick)
    state
  end

  defp now, do: System.monotonic_time(:millisecond)
end
