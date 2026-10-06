defmodule PhoenixReplay.Export.Queue.Local do
  @moduledoc """
  The default `PhoenixReplay.Export.Queue`: keeps video exports in memory
  and runs them under `PhoenixReplay.Export.TaskSupervisor`,
  `:max_concurrency` at a time, on the node that asked for them. They are
  lost when the node stops; `PhoenixReplay.Export.Queue.Oban` keeps them.

  It keeps every job until its video is `:ttl` old, broadcasts each change
  to a job on the recording's topic, and deletes expired videos. A job
  whose task crashes fails, and the next one starts. When it starts, and
  every quarter of `:ttl` from then on, it deletes the videos and
  screenshots in the export directory older than `:ttl`: those a server
  that stopped left, so they do not pile up across deploys, and those of
  exports another queue, such as `PhoenixReplay.Export.Queue.Oban`,
  rendered on this node. Other files there are left alone, so `:dir` may be shared.

  Cancelling a queued job takes it out of the queue. A running one is sent
  `{PhoenixReplay.Export, :cancel}` rather than killed, so it closes its
  browser and stops ffmpeg itself, and ends with `{:error, :cancelled}`.
  """

  use GenServer

  require Logger

  alias PhoenixReplay.Export.{Job, Queue, Video}

  @behaviour Queue

  @doc "Starts the export queue, registered under this module's name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl Queue
  def start(recording_id, config, options, _opts),
    do: GenServer.call(__MODULE__, {:start, recording_id, config, options})

  @impl Queue
  def cancel(id, _opts), do: GenServer.call(__MODULE__, {:cancel, id})

  @impl Queue
  def get(id, _opts), do: GenServer.call(__MODULE__, {:get, id})

  @impl Queue
  def latest(recording_id, _opts), do: GenServer.call(__MODULE__, {:latest, recording_id})

  @impl GenServer
  def init(nil) do
    {:ok, sweep(%{jobs: %{}, order: [], queue: :queue.new(), running: %{}})}
  end

  # The one cleanup, now and every quarter of `:ttl`: jobs finished
  # longer ago are forgotten, and their videos, with any other export's
  # files that old, deleted.
  defp sweep(state) do
    case PhoenixReplay.Config.load().export do
      %{} = export ->
        Process.send_after(self(), :sweep, div(export.ttl, 4))
        state = forget_expired(state, export.ttl)
        sweep_dir(export)
        state

      nil ->
        state
    end
  end

  defp forget_expired(state, ttl) do
    now = System.monotonic_time(:millisecond)

    {expired, kept} =
      Enum.split_with(state.order, fn id ->
        match?(%Job{finished_at: at} when is_integer(at) and now - at >= ttl, state.jobs[id])
      end)

    Enum.each(expired, fn id ->
      with %Job{path: path} when is_binary(path) <- state.jobs[id], do: File.rm(path)
    end)

    %{state | order: kept, jobs: Map.drop(state.jobs, expired)}
  end

  # Another VM may be exporting into the same directory, so only what is
  # older than its own videos may be is deleted.
  defp sweep_dir(export) do
    dir = Video.dir(export)
    cutoff = System.os_time(:second) - div(export.ttl, 1_000)

    with {:ok, names} <- File.ls(dir) do
      for name <- names,
          Job.file?(name),
          path = Path.join(dir, name),
          {:ok, %File.Stat{mtime: mtime}} <- [File.stat(path, time: :posix)],
          mtime < cutoff,
          do: File.rm_rf(path)
    end
  end

  @impl GenServer
  def handle_call({:start, recording_id, config, options}, _from, state) do
    case Enum.find(active(state), &(&1.recording_id == recording_id)) do
      %Job{} = job ->
        {:reply, {:ok, job}, state}

      nil ->
        job = Job.new(recording_id, options)

        state =
          %{
            state
            | queue: :queue.in({job.id, config}, state.queue),
              order: [job.id | state.order]
          }
          |> put(job)
          |> run_next(config)

        {:reply, {:ok, state.jobs[job.id]}, state}
    end
  end

  def handle_call({:cancel, id}, _from, state) do
    state =
      case state.jobs[id] do
        %Job{status: :queued} = job ->
          {[{^id, _config}], queue} =
            state.queue |> :queue.to_list() |> Enum.split_with(&match?({^id, _config}, &1))

          finish(%{state | queue: :queue.from_list(queue)}, %{job | status: :cancelled})

        %Job{status: :running} = job ->
          {_ref, {_id, _config, pid}} = Enum.find(state.running, &match?({_ref, {^id, _, _}}, &1))
          send(pid, {PhoenixReplay.Export, :cancel})
          put(state, %{job | status: :cancelling})

        _finished ->
          state
      end

    {:reply, :ok, state}
  end

  def handle_call({:get, id}, _from, state), do: {:reply, state.jobs[id], state}

  def handle_call({:latest, recording_id}, _from, state) do
    job =
      state.order
      |> Enum.map(&state.jobs[&1])
      |> Enum.find(&match?(%Job{recording_id: ^recording_id}, &1))

    {:reply, job, state}
  end

  @impl GenServer
  def handle_cast({:progress, id, fraction}, state) do
    progress = fraction |> Kernel.*(100) |> trunc() |> min(99) |> max(0)

    case state.jobs[id] do
      %Job{status: :running, progress: previous} = job when progress > previous ->
        {:noreply, put(state, %{job | progress: progress})}

      _unchanged ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({ref, result}, %{running: running} = state) when is_map_key(running, ref) do
    Process.demonitor(ref, [:flush])
    {{id, config, _pid}, running} = Map.pop(running, ref)

    finished =
      case result do
        {:ok, path} ->
          %{state.jobs[id] | status: :done, progress: 100, path: path}

        {:error, :cancelled} ->
          %{state.jobs[id] | status: :cancelled}

        {:error, reason} ->
          %{state.jobs[id] | status: :failed, error: Video.describe_error(reason)}
      end

    {:noreply, %{state | running: running} |> finish(finished) |> run_next(config)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{running: running} = state)
      when is_map_key(running, ref) do
    {{id, config, _pid}, running} = Map.pop(running, ref)
    Logger.error("PhoenixReplay: video export #{id} crashed: #{Exception.format_exit(reason)}")
    failed = %{state.jobs[id] | status: :failed, error: "The export crashed."}
    {:noreply, %{state | running: running} |> finish(failed) |> run_next(config)}
  end

  def handle_info(:sweep, state), do: {:noreply, sweep(state)}

  defp active(state), do: state.jobs |> Map.values() |> Enum.reject(&Job.finished?/1)

  defp run_next(state, config) do
    if map_size(state.running) < config.export.max_concurrency do
      case :queue.out(state.queue) do
        {{:value, {id, job_config}}, queue} ->
          %{state | queue: queue} |> run(state.jobs[id], job_config) |> run_next(config)

        {:empty, _queue} ->
          state
      end
    else
      state
    end
  end

  defp run(state, job, config) do
    server = self()
    progress = fn fraction -> GenServer.cast(server, {:progress, job.id, fraction}) end

    task =
      Task.Supervisor.async_nolink(PhoenixReplay.Export.TaskSupervisor, fn ->
        Video.render(job, config, progress)
      end)

    %{state | running: Map.put(state.running, task.ref, {job.id, config, task.pid})}
    |> put(%{job | status: :running, node: node()})
  end

  # A finished video is deleted once it is `:ttl` old.
  defp finish(state, job) do
    put(state, %{job | finished_at: System.monotonic_time(:millisecond)})
  end

  defp put(state, job) do
    Queue.broadcast(job)
    %{state | jobs: Map.put(state.jobs, job.id, job)}
  end
end
