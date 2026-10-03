defmodule PhoenixReplay.Recorder.Buffer do
  @moduledoc """
  ETS buffer for in-progress recordings.

  The recorded LiveView process writes its own events straight into the
  table, so recording never waits on another process. The table is created
  by `PhoenixReplay.Application` and outlives every worker, which lets
  `PhoenixReplay.Recorder.Monitor` recover sessions after a restart.

  Rows:

    * `{{id, :meta}, pid, config, recording}` — one per session
    * `{{id, seq}, event}` — one per event, `seq` counting up from `0`

  Integer keys sort before atoms, so each session's events precede its
  metadata row in the ordered set.
  """

  alias PhoenixReplay.Config
  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Event, Summary}

  @table __MODULE__

  @doc "Creates the named table. Called once from `PhoenixReplay.Application`."
  @spec create_table() :: :ok
  def create_table do
    :ets.new(@table, [:named_table, :public, :ordered_set, write_concurrency: true])
    :ok
  end

  @doc "Registers a new session recorded by `pid`. The recording's events are not stored."
  @spec open(Recording.t(), pid(), Config.t()) :: :ok
  def open(%Recording{} = recording, pid, %Config{} = config) do
    :ets.insert(@table, {{recording.id, :meta}, pid, config, %{recording | events: []}})
    :ok
  end

  @doc "Sets the session's URL. Only the recording process writes its metadata row."
  @spec put_url(Recording.id(), String.t()) :: :ok
  def put_url(id, url) do
    case :ets.lookup(@table, {id, :meta}) do
      [{key, pid, config, recording}] ->
        :ets.insert(@table, {key, pid, config, %{recording | url: url}})

      [] ->
        :ok
    end

    :ok
  end

  @doc "Appends the event with sequence number `seq`."
  @spec append(Recording.id(), non_neg_integer(), Event.t()) :: :ok
  def append(id, seq, %Event{} = event) do
    :ets.insert(@table, {{id, seq}, event})
    :ok
  end

  @doc "Returns the session's recording with all events appended so far."
  @spec fetch(Recording.id()) :: {:ok, Recording.t()} | :error
  def fetch(id) do
    case :ets.lookup(@table, {id, :meta}) do
      [{_key, _pid, _config, recording}] -> {:ok, %{recording | events: events(id)}}
      [] -> :error
    end
  end

  @doc "Returns the configuration the session was started with."
  @spec config(Recording.id()) :: {:ok, Config.t()} | :error
  def config(id) do
    case :ets.lookup(@table, {id, :meta}) do
      [{_key, _pid, config, _recording}] -> {:ok, config}
      [] -> :error
    end
  end

  @doc "Lists `{id, pid}` for every buffered session."
  @spec sessions() :: [{Recording.id(), pid()}]
  def sessions do
    :ets.select(@table, [{{{:"$1", :meta}, :"$2", :_, :_}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc "Summarizes every buffered session, most recent first."
  @spec summaries() :: [Summary.t()]
  def summaries do
    @table
    |> :ets.select([{{{:_, :meta}, :"$1", :_, :"$2"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {pid, recording} ->
      %{
        Summary.new(recording, live?: Process.alive?(pid))
        | event_count: event_count(recording.id),
          event_names: event_names(recording.id),
          duration_ms: duration_ms(recording.id)
      }
    end)
    |> Enum.sort_by(& &1.connected_at, :desc)
  end

  @doc "Removes the session and all of its events."
  @spec close(Recording.id()) :: :ok
  def close(id) do
    :ets.delete(@table, {id, :meta})
    :ets.select_delete(@table, [{{{id, :"$1"}, :_}, [{:is_integer, :"$1"}], [true]}])
    :ok
  end

  defp events(id) do
    :ets.select(@table, [{{{id, :"$1"}, :"$2"}, [{:is_integer, :"$1"}], [:"$2"]}])
  end

  defp event_count(id) do
    :ets.select_count(@table, [{{{id, :"$1"}, :_}, [{:is_integer, :"$1"}], [true]}])
  end

  defp event_names(id) do
    pattern = {{id, :_}, %{__struct__: Event, type: :event, data: %{name: :"$1"}}}
    @table |> :ets.select([{pattern, [], [:"$1"]}]) |> Enum.uniq() |> Enum.sort()
  end

  defp duration_ms(id) do
    with {^id, seq} when is_integer(seq) <- :ets.prev(@table, {id, :meta}),
         [{_key, %Event{at: at}}] <- :ets.lookup(@table, {id, seq}) do
      at
    else
      _none -> 0
    end
  end
end
