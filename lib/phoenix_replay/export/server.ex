defmodule PhoenixReplay.Export.Server do
  @moduledoc """
  Queues video exports and runs them under `PhoenixReplay.Export.TaskSupervisor`,
  `:max_concurrency` at a time.

  It keeps every job until its video is `:ttl` old, broadcasts each change
  to a job on the recording's topic, and deletes expired videos. A job
  whose task crashes fails, and the next one starts.

  Cancelling a queued job takes it out of the queue. A running one is sent
  `{PhoenixReplay.Export, :cancel}` rather than killed, so it closes its
  browser and stops ffmpeg itself, and ends with `{:error, :cancelled}`.
  """

  use GenServer

  require Logger

  alias PhoenixReplay.Config
  alias PhoenixReplay.Export.{Job, Options, Video}

  @topic "phoenix_replay:export:"

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Queues an export of a recording, unless one is queued or running."
  @spec start(PhoenixReplay.Recording.id(), Config.t(), Options.t()) :: {:ok, Job.t()}
  def start(recording_id, config, options),
    do: GenServer.call(__MODULE__, {:start, recording_id, config, options})

  @doc "Cancels the job with `id`, if it is queued or running."
  @spec cancel(Job.id()) :: :ok
  def cancel(id), do: GenServer.call(__MODULE__, {:cancel, id})

  @doc "The job with `id`."
  @spec get(Job.id()) :: Job.t() | nil
  def get(id), do: GenServer.call(__MODULE__, {:get, id})

  @doc "The latest job for a recording."
  @spec latest(PhoenixReplay.Recording.id()) :: Job.t() | nil
  def latest(recording_id), do: GenServer.call(__MODULE__, {:latest, recording_id})

  @doc "Subscribes the caller to a recording's jobs."
  @spec subscribe(PhoenixReplay.Recording.id()) :: :ok | {:error, term()}
  def subscribe(recording_id),
    do: Phoenix.PubSub.subscribe(PhoenixReplay.PubSub, @topic <> recording_id)

  @impl true
  def init(nil), do: {:ok, %{jobs: %{}, order: [], queue: :queue.new(), running: %{}}}

  @impl true
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
          {[{^id, config}], queue} =
            state.queue |> :queue.to_list() |> Enum.split_with(&match?({^id, _config}, &1))

          finish(%{state | queue: :queue.from_list(queue)}, %{job | status: :cancelled}, config)

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

  @impl true
  def handle_cast({:progress, id, fraction}, state) do
    progress = fraction |> Kernel.*(100) |> trunc() |> min(99) |> max(0)

    case state.jobs[id] do
      %Job{status: :running, progress: previous} = job when progress > previous ->
        {:noreply, put(state, %{job | progress: progress})}

      _unchanged ->
        {:noreply, state}
    end
  end

  @impl true
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

    {:noreply, %{state | running: running} |> finish(finished, config) |> run_next(config)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{running: running} = state)
      when is_map_key(running, ref) do
    {{id, config, _pid}, running} = Map.pop(running, ref)
    Logger.error("PhoenixReplay: video export #{id} crashed: #{Exception.format_exit(reason)}")
    failed = %{state.jobs[id] | status: :failed, error: "The export crashed."}
    {:noreply, %{state | running: running} |> finish(failed, config) |> run_next(config)}
  end

  def handle_info({:sweep, ttl}, state) do
    now = System.monotonic_time(:millisecond)

    {expired, kept} =
      Enum.split_with(state.order, fn id ->
        match?(%Job{finished_at: at} when is_integer(at) and now - at >= ttl, state.jobs[id])
      end)

    Enum.each(expired, fn id ->
      with %Job{path: path} when is_binary(path) <- state.jobs[id], do: File.rm(path)
    end)

    {:noreply, %{state | order: kept, jobs: Map.drop(state.jobs, expired)}}
  end

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
    |> put(%{job | status: :running})
  end

  # A finished video is deleted once it is `:ttl` old.
  defp finish(state, job, config) do
    Process.send_after(self(), {:sweep, config.export.ttl}, config.export.ttl)
    put(state, %{job | finished_at: System.monotonic_time(:millisecond)})
  end

  defp put(state, job) do
    Phoenix.PubSub.broadcast(
      PhoenixReplay.PubSub,
      @topic <> job.recording_id,
      {PhoenixReplay.Export, job}
    )

    %{state | jobs: Map.put(state.jobs, job.id, job)}
  end
end
