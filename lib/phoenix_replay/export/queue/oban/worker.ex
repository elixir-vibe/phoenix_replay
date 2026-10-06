if Code.ensure_loaded?(Oban) do
  defmodule PhoenixReplay.Export.Queue.Oban.Worker do
    @moduledoc """
    Renders one video export in Oban; see `PhoenixReplay.Export.Queue.Oban`.

    It joins a `:pg` group for its job, so `cancel/1` reaches it on any
    node, and the render stops the way `PhoenixReplay.Export.Queue.Local`
    stops one: closing its browser and stopping encoding itself. An export
    is not retried; it fails with a message for the people who asked for
    it.

    An export may run for the `:timeout` its queue was given, an hour by
    default, kept in the job's `meta`. Past it, the worker stops the render
    as a cancel would, so it closes its browser, and the export fails. Oban
    stops the job itself only a minute later, as a last resort: it kills
    the process, which leaves the browser open.
    """

    # One export of a recording at a time, for as long as it waits or runs.
    use Oban.Worker,
      max_attempts: 1,
      unique: [keys: [:recording_id], states: :incomplete, period: :infinity]

    alias PhoenixReplay.Config
    alias PhoenixReplay.Export.{Job, Queue, Video}

    # The `:pg` scope the export supervisor starts, and how often progress
    # is written to the job, in percent.
    @scope PhoenixReplay.Export
    @kept_every 10

    # How long an export may run in all, unless its queue says otherwise,
    # and how much longer Oban waits before killing it.
    @timeout :timer.hours(1)
    @grace :timer.minutes(1)

    @doc "How long an export may run in all, when its queue does not say."
    @spec default_timeout() :: pos_integer()
    def default_timeout, do: @timeout

    @impl Oban.Worker
    def timeout(%Oban.Job{} = oban_job), do: limit(oban_job) + @grace

    defp limit(%Oban.Job{meta: meta}), do: meta["timeout"] || @timeout

    @doc """
    Asks the render of the job with `id` to stop, on whichever node it runs.
    Returns `:not_running` when no render answers, as for a job its node
    left behind.
    """
    @spec cancel(Job.id()) :: :ok | :not_running
    def cancel(id) do
      case :pg.get_members(@scope, {__MODULE__, id}) do
        [] ->
          :not_running

        renders ->
          Enum.each(renders, &send(&1, {PhoenixReplay.Export, :cancel}))
          :ok
      end
    end

    @impl Oban.Worker
    def perform(%Oban.Job{} = oban_job) do
      job = %{Queue.Oban.to_job(oban_job) | status: :running, node: node()}
      :ok = :pg.join(@scope, {__MODULE__, job.id}, self())
      oban_job = keep(oban_job, %{"node" => Atom.to_string(node())})
      Queue.broadcast(job)

      # Past its time, the render is stopped as a cancel stops it.
      deadline = Process.send_after(self(), {PhoenixReplay.Export, :cancel}, limit(oban_job))
      result = Video.render(job, Config.load(), progress(oban_job, job))
      overdue? = Process.cancel_timer(deadline) == false

      case result do
        {:ok, path} ->
          keep(oban_job, %{"path" => path, "progress" => 100})
          Queue.broadcast(%{job | status: :done, progress: 100, path: path})
          :ok

        {:error, :cancelled} when not overdue? ->
          Queue.broadcast(%{job | status: :cancelled})
          {:cancel, :cancelled}

        {:error, :cancelled} ->
          fail(oban_job, job, {:too_long, limit(oban_job)})

        {:error, reason} ->
          fail(oban_job, job, reason)
      end
    end

    defp fail(oban_job, job, reason) do
      error = Video.describe_error(reason)
      keep(oban_job, %{"error" => error})
      Queue.broadcast(%{job | status: :failed, error: error})
      {:error, error}
    end

    # Each percent is broadcast; every few are kept on the job too, for a
    # player opened while it runs.
    defp progress(oban_job, job) do
      fn fraction ->
        percent = fraction |> Kernel.*(100) |> trunc() |> min(99) |> max(0)
        Queue.broadcast(%{job | progress: percent})
        if rem(percent, @kept_every) == 0, do: keep(oban_job, %{"progress" => percent})
      end
    end

    defp keep(oban_job, meta) do
      changeset = Ecto.Changeset.change(oban_job, meta: Map.merge(oban_job.meta, meta))
      {:ok, oban_job} = Oban.Repo.update(oban_job.conf, changeset)
      oban_job
    end
  end
end
