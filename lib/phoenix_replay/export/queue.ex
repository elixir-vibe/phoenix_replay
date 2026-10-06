defmodule PhoenixReplay.Export.Queue do
  @moduledoc """
  Where video exports wait their turn and run.

  `PhoenixReplay.Export.Queue.Local`, the default, keeps them in memory on
  the node that asked for them. `PhoenixReplay.Export.Queue.Oban` keeps
  them in your Oban queue, so they survive restarts and run on any node
  of a cluster. The `:queue` option of `:export` chooses one: a module, or
  `{module, opts}`.

  Either way, every change to a job is broadcast with `broadcast/1`, so
  `PhoenixReplay.Export.subscribe/1` follows jobs from either.
  """

  alias PhoenixReplay.Config
  alias PhoenixReplay.Export.{Job, Options}
  alias PhoenixReplay.Recording

  @typedoc "A queue module and its options."
  @type t :: {module(), keyword()}

  @doc """
  Queues an export of a recording, unless one is queued or running, which
  is returned instead.
  """
  @callback start(Recording.id(), Config.t(), Options.t(), keyword()) :: {:ok, Job.t()}

  @doc """
  Cancels the job with `id`, if it is queued or running. A running one is
  asked to stop, and ends `:cancelled`.
  """
  @callback cancel(Job.id(), keyword()) :: :ok

  @doc "The job with `id`, if it is still kept."
  @callback get(Job.id(), keyword()) :: Job.t() | nil

  @doc "The latest job for a recording, if one is kept."
  @callback latest(Recording.id(), keyword()) :: Job.t() | nil

  @topic "phoenix_replay:export:"

  @doc "The queue `config` exports through."
  @spec of(Config.t()) :: t()
  def of(%Config{export: %{queue: {module, opts}}}), do: {module, opts}

  def of(%Config{export: %{queue: module}}) when is_atom(module) and module != nil,
    do: {module, []}

  def of(%Config{}), do: {PhoenixReplay.Export.Queue.Local, []}

  @doc """
  Tells subscribers of the job's recording that it changed. Nobody may be
  listening, and the export goes on either way.
  """
  @spec broadcast(Job.t()) :: :ok
  def broadcast(%Job{} = job) do
    _delivered =
      Phoenix.PubSub.broadcast(
        PhoenixReplay.PubSub,
        @topic <> job.recording_id,
        {PhoenixReplay.Export, job}
      )

    :ok
  end

  @doc "Subscribes the caller to the jobs of a recording; see `broadcast/1`."
  @spec subscribe(Recording.id()) :: :ok | {:error, term()}
  def subscribe(recording_id),
    do: Phoenix.PubSub.subscribe(PhoenixReplay.PubSub, @topic <> recording_id)
end
