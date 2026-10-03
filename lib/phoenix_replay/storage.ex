# reach:disable-next-line behaviour_candidate -- this module is the behaviour; its functions are the dispatching facade
defmodule PhoenixReplay.Storage do
  @moduledoc """
  Behaviour for finished-recording storage, and the facade used to call it.

  In-progress recordings live in `PhoenixReplay.Recorder.Buffer`. When the
  recorded LiveView exits, the recording is saved through the configured
  backend.

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
end
