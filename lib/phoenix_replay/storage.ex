# reach:disable-next-line behaviour_candidate -- this module is the behaviour; its functions are the dispatching facade
defmodule PhoenixReplay.Storage do
  @moduledoc """
  Behaviour for finished-recording storage, and the facade used to call it.

  In-progress recordings live in `PhoenixReplay.Recorder.Buffer`. When the
  recorded LiveView exits, the recording is saved through the configured
  backend.

  A backend that implements the optional `append/2`, `fetch_partial/2` and
  `partials/1` callbacks also receives running sessions in chunks, as
  `:flush` configures, so they survive a crash of the node and their
  events leave memory. `save/2` then replaces the chunks with the finished
  recording. `PhoenixReplay.Storage.File` implements them; other backends
  save each recording once, when it ends.

  ## Built-in backends

    * `PhoenixReplay.Storage.File` — one file per recording on disk (default)
    * `PhoenixReplay.Storage.Ecto` — a database table via an Ecto repo

  ## Configuration

      config :phoenix_replay,
        storage: {PhoenixReplay.Storage.File, path: "priv/replay_recordings"}

  ## Implementing a backend

  Callbacks receive the options from the `{module, opts}` tuple as their last
  argument. `list/1` must return summaries without decoding full recordings,
  ordered most recent first.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Summary

  @type t :: PhoenixReplay.Config.storage()

  @callback save(Recording.t(), keyword()) :: :ok | {:error, term()}
  @callback fetch(Recording.id(), keyword()) :: {:ok, Recording.t()} | {:error, term()}
  @callback list(keyword()) :: [Summary.t()]
  @callback delete(Recording.id(), keyword()) :: :ok | {:error, term()}
  @callback clear(keyword()) :: :ok | {:error, term()}

  @typedoc "Events of a chunk with their sequence numbers, which order them."
  @type chunk :: [{non_neg_integer(), PhoenixReplay.Recording.Event.t()}]

  @doc """
  Appends a chunk of a running session. `recording` carries the session's
  current metadata; the latest appended metadata wins.
  """
  @callback append(recording :: Recording.t(), chunk(), keyword()) :: :ok | {:error, term()}

  @doc """
  Reads the chunks appended for a session, with events ordered by sequence
  number. Returns `{:error, :not_found}` when none were appended.
  """
  @callback fetch_partial(Recording.id(), keyword()) :: {:ok, Recording.t()} | {:error, term()}

  @doc "Lists the ids of sessions with appended chunks this node did not finish."
  @callback partials(keyword()) :: [Recording.id()]

  @optional_callbacks append: 3, fetch_partial: 2, partials: 1

  @doc "Persists a finished recording."
  @spec save(t(), Recording.t()) :: :ok | {:error, term()}
  def save({module, opts}, %Recording{} = recording), do: module.save(recording, opts)

  @doc "Fetches a recording by id."
  @spec fetch(t(), Recording.id()) :: {:ok, Recording.t()} | {:error, term()}
  def fetch({module, opts}, id), do: module.fetch(id, opts)

  @doc "Lists stored recording summaries, most recent first."
  @spec list(t()) :: [Summary.t()]
  def list({module, opts}), do: module.list(opts)

  @doc "Deletes a recording by id."
  @spec delete(t(), Recording.id()) :: :ok | {:error, term()}
  def delete({module, opts}, id), do: module.delete(id, opts)

  @doc "Deletes every stored recording."
  @spec clear(t()) :: :ok | {:error, term()}
  def clear({module, opts}), do: module.clear(opts)

  @doc "Returns true when the backend takes running sessions in chunks."
  @spec chunked?(t()) :: boolean()
  def chunked?({module, _opts}) do
    Code.ensure_loaded?(module) and function_exported?(module, :append, 3)
  end

  @doc "Appends a chunk of a running session. See `c:append/3`."
  @spec append(t(), Recording.t(), chunk()) :: :ok | {:error, term()}
  def append({module, opts}, %Recording{} = recording, chunk),
    do: module.append(recording, chunk, opts)

  @doc "Reads the chunks appended for a session. See `c:fetch_partial/2`."
  @spec fetch_partial(t(), Recording.id()) :: {:ok, Recording.t()} | {:error, term()}
  def fetch_partial({module, opts}, id), do: module.fetch_partial(id, opts)

  @doc "Lists sessions with chunks this node did not finish. See `c:partials/1`."
  @spec partials(t()) :: [Recording.id()]
  def partials({module, opts}) do
    if chunked?({module, opts}), do: module.partials(opts), else: []
  end
end
