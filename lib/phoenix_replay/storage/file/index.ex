defmodule PhoenixReplay.Storage.File.Index do
  @moduledoc """
  Keeps `PhoenixReplay.Storage.File`'s summaries in memory once read, and
  the directory relative `:path`s resolve against.

  Started with the application when file storage is configured; see
  `c:PhoenixReplay.Storage.child_spec/1`. If this process restarts,
  summaries are read from disk again as needed. While it is not running,
  as for a file storage configured by hand while the application runs
  another backend, it caches nothing and every listing reads from disk.
  """

  use GenServer

  import Ex2ms

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Summary

  @table __MODULE__
  @root {__MODULE__, :root}

  @doc "Starts the index, registered under its module name."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  The directory relative paths resolve against: the working directory when
  the index first started. The working directory belongs to the whole VM,
  and tools such as Phoenix's code reloader change it while they compile.
  """
  @spec root() :: Path.t()
  def root, do: :persistent_term.get(@root, nil) || File.cwd!()

  @doc "The summaries indexed for `dir`."
  @spec summaries(Path.t()) :: [Summary.t()]
  def summaries(dir) do
    if running?(),
      do: :ets.select(@table, fun(do: ({{^dir, _id}, summary} -> summary))),
      else: []
  end

  @doc "Indexes summaries of `dir` by id."
  @spec put(Path.t(), [{Recording.id(), Summary.t()}]) :: :ok
  def put(dir, entries) do
    if running?(),
      do: :ets.insert(@table, for({id, summary} <- entries, do: {{dir, id}, summary}))

    :ok
  end

  @doc "Forgets the summary of `id` in `dir`."
  @spec delete(Path.t(), Recording.id()) :: :ok
  def delete(dir, id) do
    if running?(), do: :ets.delete(@table, {dir, id})
    :ok
  end

  @doc "Forgets every summary of `dir`."
  @spec clear(Path.t()) :: :ok
  def clear(dir) do
    if running?(), do: :ets.match_delete(@table, {{dir, :_}, :_})
    :ok
  end

  @impl true
  def init(_opts) do
    # Kept from the first start: a restart may happen in another directory.
    if :persistent_term.get(@root, nil) == nil, do: :persistent_term.put(@root, File.cwd!())
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  defp running?, do: :ets.whereis(@table) != :undefined
end
