if Code.ensure_loaded?(Oban) do
  defmodule PhoenixReplay.Export.Queue.Oban do
    @moduledoc """
    A `PhoenixReplay.Export.Queue` in your [Oban](https://hexdocs.pm/oban)
    queue: exports survive restarts and deploys, and run on whichever node
    of a cluster takes them.

        config :phoenix_replay,
          export: [
            endpoint: MyAppWeb.Endpoint,
            queue: {PhoenixReplay.Export.Queue.Oban, oban: Oban, queue: :replay_exports}
          ]

        config :my_app, Oban, queues: [replay_exports: 1]

    The options:

      * `:oban` — your Oban instance (default `Oban`)
      * `:queue` — the queue (default `:replay_exports`), whose limit is
        how many videos are exported at once, instead of `:max_concurrency`
      * `:timeout` — milliseconds an export may run in all before Oban
        stops it (default one hour), as `c:Oban.Worker.timeout/1`

    Every node that runs the queue needs Chromium and `ffmpeg`.

    Oban keeps one export of a recording at a time, by its unique jobs. A
    job's progress is broadcast as it renders, and kept in its `meta` now
    and then, with the node whose disk the video is on. A queued job is
    cancelled in Oban; a running one is asked to stop, wherever it runs, so
    it closes its browser and stops encoding itself, rather than killed, as
    `Oban.cancel_job/2` would. A running job no node renders any more is
    cancelled in Oban. Videos are deleted after `:ttl`, and from then on the
    job is no longer listed.

    ## In production

    As Oban's guide advises, run its plugins:

      * `Oban.Plugins.Lifeline`, so an export a deploy or a crash left
        `executing` is rescued. Exports are not retried, so it ends
        failed, and the recording can be exported again.
      * `Oban.Plugins.Pruner`, so finished jobs are deleted; they are no
        longer listed once their video is gone, after `:ttl`.

    Progress and the video's place are written to the job's `meta` while
    it runs. Open-source Oban has no API for progress, and documents none
    for this; it works because finishing a job changes only its state and
    timestamps.
    """

    @behaviour PhoenixReplay.Export.Queue

    import Ecto.Query, only: [from: 2]

    alias PhoenixReplay.Config
    alias PhoenixReplay.Export.{Job, Options, Queue}
    alias __MODULE__.Worker

    @prefix "oban-"

    @impl Queue
    def start(recording_id, _config, options, opts) do
      args = %{"recording_id" => recording_id, "options" => Options.to_map(options)}

      changeset =
        Worker.new(args,
          queue: Keyword.get(opts, :queue, :replay_exports),
          meta: %{"timeout" => Keyword.get(opts, :timeout, Worker.default_timeout())}
        )

      {:ok, oban_job} = Oban.insert(name(opts), changeset)

      job = to_job(oban_job)
      unless oban_job.conflict?, do: Queue.broadcast(job)
      {:ok, job}
    end

    @impl Queue
    def cancel(id, opts) do
      case get(id, opts) do
        %Job{status: :queued} = job ->
          :ok = Oban.cancel_job(name(opts), oban_id(id))
          Queue.broadcast(%{job | status: :cancelled})

        %Job{status: :running} = job ->
          cancel_running(job, opts)

        _finished ->
          :ok
      end

      :ok
    end

    @impl Queue
    def get(@prefix <> number = id, opts) do
      with {oban_id, ""} <- Integer.parse(number),
           %Oban.Job{} = oban_job <- Oban.Repo.get(config(opts), Oban.Job, oban_id),
           true <- oban_job.worker == worker_name(),
           %Job{} = job <- kept(to_job(oban_job)) do
        if job.id == id, do: job
      else
        _missing -> nil
      end
    end

    def get(_id, _opts), do: nil

    @impl Queue
    def latest(recording_id, opts) do
      query =
        from(j in Oban.Job,
          where: j.worker == ^worker_name() and j.args["recording_id"] == ^recording_id,
          order_by: [desc: j.id],
          limit: 1
        )

      case Oban.Repo.one(config(opts), query) do
        %Oban.Job{} = oban_job -> kept(to_job(oban_job))
        nil -> nil
      end
    end

    @doc """
    The export an Oban job is: its id prefixed `oban-`, its status from the
    job's state, and its progress, video and error from the job's `meta`.
    """
    @spec to_job(Oban.Job.t()) :: Job.t()
    def to_job(%Oban.Job{id: id, args: args, meta: meta} = oban_job) do
      %Job{
        id: @prefix <> Integer.to_string(id),
        recording_id: args["recording_id"],
        options: Options.from_map(args["options"]),
        status: status(oban_job.state, meta),
        progress: if(oban_job.state == "completed", do: 100, else: meta["progress"] || 0),
        path: meta["path"],
        node: node_of(meta["node"]),
        error: meta["error"],
        finished_at: finished_at(oban_job)
      }
    end

    defp status(state, _meta) when state in ~w(available scheduled retryable suspended),
      do: :queued

    defp status("executing", %{"cancelling" => true}), do: :cancelling
    defp status("executing", _meta), do: :running
    defp status("completed", _meta), do: :done
    defp status("cancelled", _meta), do: :cancelled
    defp status("discarded", _meta), do: :failed

    # When the job finished, in Unix milliseconds.
    defp finished_at(oban_job) do
      case oban_job.completed_at || oban_job.cancelled_at || oban_job.discarded_at do
        nil -> nil
        at -> DateTime.to_unix(at, :millisecond)
      end
    end

    # A finished export is kept for `:ttl`, as its video is.
    defp kept(%Job{finished_at: nil} = job), do: job

    defp kept(%Job{finished_at: at} = job) do
      if System.system_time(:millisecond) - at < Config.load().export.ttl, do: job
    end

    # A node this one does not know cannot serve the video anyway.
    defp node_of(nil), do: nil

    defp node_of(name) do
      String.to_existing_atom(name)
    rescue
      ArgumentError -> nil
    end

    defp oban_id(@prefix <> number), do: String.to_integer(number)

    # A render asked to stop closes its browser and stops encoding itself.
    # One no node runs any more, left behind by a deploy or a crash, is
    # cancelled in Oban.
    defp cancel_running(job, opts) do
      case Worker.cancel(job.id) do
        :ok ->
          mark_cancelling(oban_id(job.id), opts)
          Queue.broadcast(%{job | status: :cancelling})

        :not_running ->
          :ok = Oban.cancel_job(name(opts), oban_id(job.id))
          Queue.broadcast(%{job | status: :cancelled})
      end
    end

    # So a player opened while it stops says so.
    defp mark_cancelling(oban_id, opts) do
      with %Oban.Job{} = oban_job <- Oban.Repo.get(config(opts), Oban.Job, oban_id) do
        changeset =
          Ecto.Changeset.change(oban_job, meta: Map.put(oban_job.meta, "cancelling", true))

        Oban.Repo.update(config(opts), changeset)
      end
    end

    defp worker_name, do: inspect(Worker)

    defp name(opts), do: Keyword.get(opts, :oban, Oban)
    defp config(opts), do: Oban.config(name(opts))
  end
end
