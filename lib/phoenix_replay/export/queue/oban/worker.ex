if Code.ensure_loaded?(Oban) do
  defmodule PhoenixReplay.Export.Queue.Oban.Worker do
    @moduledoc """
    Renders one video export in Oban; see `PhoenixReplay.Export.Queue.Oban`.

    It joins a `:pg` group for its job, so `cancel/1` reaches it on any
    node, and the render stops the way `PhoenixReplay.Export.Queue.Local`
    stops one: closing its browser and stopping encoding itself. An export
    is not retried; it fails with a message for the people who asked for
    it.
    """

    use Oban.Worker,
      max_attempts: 1,
      unique: [keys: [:recording_id], states: :incomplete]

    alias PhoenixReplay.Config
    alias PhoenixReplay.Export.{Job, Queue, Video}

    # The `:pg` scope the export supervisor starts, and how often progress
    # is written to the job, in percent.
    @scope PhoenixReplay.Export
    @kept_every 10

    @doc "Asks the render of the job with `id` to stop, on whichever node it runs."
    @spec cancel(Job.id()) :: :ok
    def cancel(id) do
      for pid <- :pg.get_members(@scope, {__MODULE__, id}),
          do: send(pid, {PhoenixReplay.Export, :cancel})

      :ok
    end

    @impl Oban.Worker
    def perform(%Oban.Job{} = oban_job) do
      job = %{Queue.Oban.to_job(oban_job) | status: :running, node: node()}
      :ok = :pg.join(@scope, {__MODULE__, job.id}, self())
      oban_job = keep(oban_job, %{"node" => Atom.to_string(node())})
      Queue.broadcast(job)

      case Video.render(job, Config.load(), progress(oban_job, job)) do
        {:ok, path} ->
          keep(oban_job, %{"path" => path, "progress" => 100})
          Queue.broadcast(%{job | status: :done, progress: 100, path: path})
          :ok

        {:error, :cancelled} ->
          Queue.broadcast(%{job | status: :cancelled})
          {:cancel, :cancelled}

        {:error, reason} ->
          error = Video.describe_error(reason)
          keep(oban_job, %{"error" => error})
          Queue.broadcast(%{job | status: :failed, error: error})
          {:error, error}
      end
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
