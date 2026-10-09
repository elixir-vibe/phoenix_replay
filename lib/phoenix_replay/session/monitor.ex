defmodule PhoenixReplay.Session.Monitor do
  @moduledoc """
  Follows each recorded session from its first event to storage.

  Each recorded process is monitored. While it runs, the monitor checks
  its sessions periodically and writes a session's buffered events to
  storage as a chunk, with `PhoenixReplay.Session.Flusher`, once
  `PhoenixReplay.Session.TailSampling` decides to keep it and `:flush` says a
  chunk is due. Keeping is decided from the events seen so far, which are
  observed incrementally, and never turns back, so nothing is written that
  would be discarded later.

  When the process exits abnormally, its exit reason is recorded as an
  `:exit` event. The session is then discarded, or saved by
  `PhoenixReplay.Session.Finalizer` in a supervised task, after any flush
  in flight. The task closes the buffer once it saved the recording or gave
  up, and emits its `PhoenixReplay.Telemetry` event after that, so a
  handler observes the finished state. Sessions being saved are marked in
  the buffer, so a restarted monitor leaves them to their task.

  Recordings are kept by visit: a recording is saved when it or another
  recording of its visit is kept, and a recording that would be discarded
  is held until its visit is kept or ends; see
  `PhoenixReplay.Session.Visits`. A recording without a visit is decided
  alone.

  On shutdown the monitor waits for saves and flushes in flight. On start
  it re-attaches to every session already in
  `PhoenixReplay.Session.Buffer`, so a restart loses no recordings.
  """

  use GenServer

  require Logger

  alias PhoenixReplay.{Catalog, Config, Storage, Telemetry}
  alias PhoenixReplay.Session.{Buffer, Finalizer, Flusher, TailSampling, Visits}

  @max_reason 4_000
  @max_tick 1_000
  # The longest wait between checks for visits that ended.
  @max_sweep 5_000
  @drain_timeout 25_000

  @doc "Starts the monitor registered under its module name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Gives the monitor time to drain on shutdown: the application waits for
  recordings being saved or written when it stops.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, shutdown: @drain_timeout + 5_000}
  end

  @doc "Starts monitoring the session recorded by `pid`."
  @spec watch(pid(), PhoenixReplay.Recording.id()) :: :ok
  def watch(pid, id), do: GenServer.cast(__MODULE__, {:watch, pid, id})

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{sessions: %{}, tracks: %{}, tasks: %{}, tick: nil, visits: Visits.new(), sweep?: false},
     {:continue, :recover}}
  end

  @impl true
  def handle_continue(:recover, state) do
    {:noreply,
     Enum.reduce(Buffer.sessions(), state, fn {id, pid}, acc -> watch(acc, pid, id) end)}
  end

  @impl true
  def handle_cast({:watch, pid, id}, state) do
    :ok = Catalog.broadcast_change()
    {:noreply, watch(state, pid, id)}
  end

  @impl true
  def handle_info(:tick, state) do
    state =
      Enum.reduce(state.tracks, %{state | tick: nil}, fn {id, track}, acc ->
        check(acc, id, track)
      end)

    {:noreply, Enum.reduce(Map.keys(state.tracks), state, &keep_ticking(&2, &1))}
  end

  def handle_info(:sweep, state) do
    {visits, ended} = Visits.expire(state.visits, now())

    for {id, reason} <- ended do
      close(id)
      Telemetry.discarded(id, reason)
    end

    {:noreply, sweep(%{state | visits: visits, sweep?: false})}
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
    # A session's configuration is fixed when it opens, so each check reads
    # it from here rather than copying it out of the buffer.
    {flush, keep, timeout} =
      case Buffer.config(id) do
        {:ok, config} ->
          {if(Storage.chunked?(config.storage), do: config.flush), config.keep,
           Config.visit_timeout(config)}

        :error ->
          {nil, nil, nil}
      end

    visit = Buffer.visit(id)

    visits =
      if visit && timeout,
        do: Visits.started(state.visits, visit, id, timeout),
        else: state.visits

    track = %{
      flush: flush,
      keep: keep,
      visit: visit,
      observation: TailSampling.new(),
      checked: -1,
      committed?: Buffer.flushed?(id),
      flushed_at: now(),
      flushing?: false,
      ended?: false
    }

    keep_ticking(
      %{
        state
        | sessions: Map.put(state.sessions, Process.monitor(pid), id),
          tracks: Map.put(state.tracks, id, track),
          visits: visits
      }
      |> sweep(),
      id
    )
  end

  # One timer runs while a watched session flushes, at the shortest
  # interval among them, so each session's own `:flush` applies.
  defp keep_ticking(state, id) do
    case state.tracks do
      %{^id => %{flush: %{interval: interval}}} -> schedule_tick(state, min(interval, @max_tick))
      %{} -> state
    end
  end

  defp schedule_tick(%{tick: nil} = state, period) do
    Process.send_after(self(), :tick, period)
    %{state | tick: period}
  end

  defp schedule_tick(%{tick: tick} = state, period), do: %{state | tick: min(tick, period)}

  ## Flushing

  defp check(state, _id, %{flush: nil}), do: state
  defp check(state, _id, %{flushing?: true}), do: state
  defp check(state, _id, %{ended?: true}), do: state

  defp check(state, id, track) do
    if due?(Buffer.pending_count(id), track) do
      committed? = track.committed?
      track = observe(track, id, Visits.kept?(state.visits, track.visit))
      # A recording kept on its own keeps its visit, saving what was held for it.
      state =
        if track.committed? and not committed?, do: keep_visit(state, track.visit), else: state

      if track.committed?, do: start_flush(state, id, track), else: put_track(state, id, track)
    else
      state
    end
  end

  defp due?(0, _track), do: false

  defp due?(pending, %{flush: flush} = track),
    do: pending >= flush.events or now() - track.flushed_at >= flush.interval

  defp observe(%{committed?: true} = track, _id, _visit_kept?), do: track
  defp observe(track, _id, true), do: %{track | committed?: true}

  defp observe(track, id, false) do
    events = Buffer.pending(id, track.checked)

    observation =
      TailSampling.observe(track.observation, Enum.map(events, &elem(&1, 1)), track.keep)

    {:ok, draw} = Buffer.draw(id)

    %{
      track
      | observation: observation,
        checked: Enum.reduce(events, track.checked, fn {seq, _event}, acc -> max(seq, acc) end),
        committed?: TailSampling.decision(observation, track.keep, draw) == :keep
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
    visit = Buffer.visit(id)

    with {:ok, recording} <- Buffer.fetch(id),
         {:ok, config} <- Buffer.config(id) do
      case decide(state, id, visit, recording, config) do
        :keep ->
          state
          |> visit_ended(visit, id)
          |> save(id, recording, config)
          |> keep_visit(visit)

        {:discard, reason} when visit != nil ->
          hold(state, visit, id, reason, config)

        {:discard, reason} ->
          close(id)
          Telemetry.discarded(id, reason)
          state
      end
    else
      :error -> state
    end
  end

  defp decide(state, id, visit, recording, config) do
    if Visits.kept?(state.visits, visit), do: :keep, else: keep(id, recording, config)
  end

  defp save(state, id, recording, config) do
    :ok = Buffer.mark_saving(id)

    task =
      Task.Supervisor.async_nolink(PhoenixReplay.TaskSupervisor, Finalizer, :finish, [
        recording,
        config
      ])

    %{state | tasks: Map.put(state.tasks, task.ref, %{kind: :save, id: id, task: task})}
  end

  # Keeping a visit saves the recordings held for it.
  defp keep_visit(state, nil), do: state

  defp keep_visit(state, visit) do
    {visits, held} = Visits.keep(state.visits, visit)

    Enum.reduce(held, %{state | visits: visits}, fn id, acc ->
      with {:ok, recording} <- Buffer.fetch(id),
           {:ok, config} <- Buffer.config(id) do
        save(acc, id, recording, config)
      else
        :error -> acc
      end
    end)
  end

  defp visit_ended(state, nil, _id), do: state

  defp visit_ended(state, visit, id),
    do: %{state | visits: Visits.ended(state.visits, visit, id, now())}

  # Its events stay buffered until the visit decides.
  defp hold(state, visit, id, reason, config) do
    :ok = Buffer.hold(id)
    Catalog.broadcast_change()

    %{state | visits: Visits.hold(state.visits, visit, id, reason, now())}
    |> evict(config.max_memory)
    |> sweep()
  end

  # Held recordings count towards `:max_memory`: those of the visit idle
  # longest go first.
  defp evict(state, nil), do: state

  defp evict(state, max_memory) do
    with true <- Buffer.memory() > max_memory,
         {visits, [_first | _rest] = released} <- Visits.release_oldest(state.visits) do
      for {id, _reason} <- released do
        close(id)
        Telemetry.discarded(id, :max_memory)
      end

      evict(%{state | visits: visits}, max_memory)
    else
      _within -> state
    end
  end

  # Checks for ended visits while any is open, as often as the shortest
  # timeout among them needs, and at least every few seconds.
  defp sweep(%{sweep?: true} = state), do: state

  defp sweep(state) do
    if Visits.any?(state.visits) do
      period =
        state.visits |> Map.values() |> Enum.map(& &1.timeout) |> Enum.min() |> min(@max_sweep)

      Process.send_after(self(), :sweep, period)
      %{state | sweep?: true}
    else
      state
    end
  end

  # A session that flushed chunks was kept, and keeping never turns back.
  defp keep(id, recording, config) do
    if Buffer.flushed?(id) do
      :keep
    else
      {:ok, draw} = Buffer.draw(id)
      TailSampling.decide(recording, config.keep, draw)
    end
  end

  defp completed(state, %{kind: :flush, id: id}, result) do
    if result != :ok do
      Logger.error("PhoenixReplay: flushing recording #{id} failed: #{inspect(result)}")
    end

    flushed(state, id)
  end

  # The save task closed the session and reported its outcome itself.
  defp completed(state, %{kind: :save}, _result), do: state

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
    with {:ok, session, _sanitizer} <- Buffer.attribute([pid]) do
      text = reason |> Exception.format_exit() |> String.slice(0, @max_reason)
      Buffer.collect(session, :exit, %{reason: text}, "exit", 1)
    end
  end

  defp put_track(state, id, track), do: %{state | tracks: Map.put(state.tracks, id, track)}

  defp close(id) do
    :ok = Buffer.close(id)
    Catalog.broadcast_change()
  end

  defp now, do: System.monotonic_time(:millisecond)
end
