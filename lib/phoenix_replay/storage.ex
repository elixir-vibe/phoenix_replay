defmodule PhoenixReplay.Storage do
  @moduledoc """
  Behaviour for persistent recording storage backends.

  Active (in-flight) recordings always live in ETS for performance.
  When a LiveView process exits, the recording is finalized and
  persisted through the configured storage backend.

  ## Built-in backends

    * `PhoenixReplay.Storage.File` — writes recordings to disk (default)
    * `PhoenixReplay.Storage.Ecto` — stores recordings in a database via Ecto

  ## Configuration

      config :phoenix_replay,
        storage: PhoenixReplay.Storage.File,
        storage_opts: [
          path: "priv/replay_recordings",
          format: :etf  # or :json
        ]

  ## Serialization formats

    * `:etf` — Erlang External Term Format (`:erlang.term_to_binary/2` with
      built-in compression). Fast, compact, preserves all Elixir types. Default.
    * `:json` — JSON via `Jason`. Portable, human-readable, but lossy for atoms,
      tuples, and structs.
  """

  alias PhoenixReplay.Recording

  @type opts :: keyword()

  @doc "Initialize the backend (create tables, directories, etc)."
  @callback init(opts()) :: :ok | {:error, term()}

  @doc "Persist a finalized recording."
  @callback save(Recording.t(), opts()) :: :ok | {:error, term()}

  @doc "Retrieve a recording by ID."
  @callback get(binary(), opts()) :: {:ok, Recording.t()} | :error

  @doc "List all recordings, most recent first."
  @callback list(opts()) :: [Recording.t()]

  @doc "List lightweight recording summaries, most recent first."
  @callback list_summaries(opts()) :: [map()]

  @optional_callbacks list_summaries: 1

  @doc "Delete a recording by ID."
  @callback delete(binary(), opts()) :: :ok | {:error, term()}

  @doc "Delete all recordings."
  @callback clear(opts()) :: :ok

  @doc "Returns the configured storage backend module."
  def backend do
    Application.get_env(:phoenix_replay, :storage, PhoenixReplay.Storage.File)
  end

  @doc "Returns the configured storage options."
  def storage_opts do
    Application.get_env(:phoenix_replay, :storage_opts, [])
  end
end
