defmodule PhoenixReplay.Recorder.Buffer do
  @moduledoc """
  ETS buffer for in-progress recordings.

  The recorded LiveView process writes its own events straight into the
  table, so recording never waits on another process. Events from the view,
  its LiveComponents and its collectors share one counter, so they stay in
  order. The
  table is created by `PhoenixReplay.Application` and outlives every worker,
  which lets `PhoenixReplay.Recorder.Monitor` recover sessions after a restart.

  Rows:

    * `{{id, :meta}, pid, config, recording}` — one per session
    * `{{id, :seq}, seq, live}` — events stored so far, and LiveView events
      seen so far including those beyond `:max_events`
    * `{{:process, pid}, id, started_at, config}` — finds the session of the
      calling process
    * `{{:collected, id, name}, count, limit}` — events a collector captured
      for the session, including those beyond its `:limit`
    * `{{id, seq}, event}` — one per event, `seq` counting up from `0`

  Integer keys sort before atoms, so each session's events precede its
  metadata rows in the ordered set.
  """

  alias PhoenixReplay.Config
  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Event, Summary}

  @table __MODULE__

  @typedoc "A buffered session found by `attribute/1`."
  @opaque session :: {Recording.id(), integer(), Config.t()}

  @doc "Creates the named table. Called once from `PhoenixReplay.Application`."
  @spec create_table() :: :ok
  def create_table do
    :ets.new(@table, [:named_table, :public, :ordered_set, write_concurrency: true])
    :ok
  end

  @doc """
  Registers a new session recorded by `pid`. The recording's events are not stored.

  Event offsets are measured from this call.
  """
  @spec open(Recording.t(), pid(), Config.t()) :: :ok
  def open(%Recording{id: id} = recording, pid, %Config{} = config) do
    :ets.insert(@table, [
      {{id, :meta}, pid, config, %{recording | events: []}},
      {{id, :seq}, 0, 0},
      {{:process, pid}, id, System.monotonic_time(:millisecond), config}
    ])

    :ok
  end

  @doc "Returns the id and configuration of the session `pid` records, if any."
  @spec session(pid()) :: {:ok, Recording.id(), Config.t()} | :error
  def session(pid) do
    case :ets.lookup(@table, {:process, pid}) do
      [{_key, id, _started_at, config}] -> {:ok, id, config}
      [] -> :error
    end
  end

  @doc """
  Appends an event to the session recorded by `pid`.

  Returns `:full` once the session reached its `:max_events`, and `:error`
  when `pid` records no session.
  """
  @spec record(pid(), Event.type(), map()) :: :ok | :full | :error
  def record(pid, type, data) do
    case :ets.lookup(@table, {:process, pid}) do
      [{_key, id, started_at, config}] ->
        if :ets.update_counter(@table, {id, :seq}, {3, 1}) <= config.max_events,
          do: write(id, started_at, type, data),
          else: :full

      [] ->
        :error
    end
  end

  @doc """
  Finds the session recorded by the first of `pids` that records one.

  Collectors pass the emitting process followed by its `$callers`, so
  events from tasks a LiveView started belong to its session.
  """
  @spec attribute([pid()]) :: {:ok, session(), Config.t()} | :error
  def attribute([]), do: :error

  def attribute([pid | rest]) do
    case :ets.lookup(@table, {:process, pid}) do
      [{_key, id, started_at, config}] -> {:ok, {id, started_at, config}, config}
      [] -> attribute(rest)
    end
  end

  @doc """
  Appends a collected event to a session found by `attribute/1`.

  Events are counted per collector `name`; once `limit` is reached they
  are counted but not stored, and `fetch/1` reports them as dropped.
  Collected events do not count towards `:max_events`.
  """
  @spec collect(session(), Event.type(), map(), String.t(), pos_integer()) :: :ok | :dropped
  def collect({id, started_at, _config}, type, data, name, limit) do
    key = {:collected, id, name}

    if :ets.update_counter(@table, key, {2, 1}, {key, 0, limit}) <= limit,
      do: write(id, started_at, type, data),
      else: :dropped
  end

  @doc "Approximate memory used by every buffered session, in bytes."
  @spec memory() :: non_neg_integer()
  def memory, do: :ets.info(@table, :memory) * :erlang.system_info(:wordsize)

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

  @doc "Stores the event with sequence number `seq`, as `record/3` does."
  @spec append(Recording.id(), non_neg_integer(), Event.t()) :: :ok
  def append(id, seq, %Event{} = event) do
    :ets.insert(@table, {{id, seq}, event})
    :ok
  end

  @doc "Returns the session's recording with all events appended so far."
  @spec fetch(Recording.id()) :: {:ok, Recording.t()} | :error
  def fetch(id) do
    case :ets.lookup(@table, {id, :meta}) do
      [{_key, _pid, _config, recording}] ->
        {:ok, %{recording | events: events(id), dropped: dropped(id)}}

      [] ->
        :error
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
          error_count: error_count(recording.id),
          duration_ms: duration_ms(recording.id)
      }
    end)
    |> Enum.sort_by(& &1.connected_at, :desc)
  end

  @doc "Removes the session and all of its events."
  @spec close(Recording.id()) :: :ok
  def close(id) do
    :ets.match_delete(@table, {{:process, :_}, id, :_, :_})
    :ets.match_delete(@table, {{:collected, id, :_}, :_, :_})
    :ets.delete(@table, {id, :seq})
    :ets.delete(@table, {id, :meta})
    :ets.select_delete(@table, [{{{id, :"$1"}, :_}, [{:is_integer, :"$1"}], [true]}])
    :ok
  end

  defp write(id, started_at, type, data) do
    seq = :ets.update_counter(@table, {id, :seq}, {2, 1}) - 1
    at = System.monotonic_time(:millisecond) - started_at
    append(id, seq, %Event{at: at, type: type, data: data})
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

  defp dropped(id) do
    @table
    |> :ets.select([
      {{{:collected, id, :"$1"}, :"$2", :"$3"}, [{:>, :"$2", :"$3"}],
       [{{:"$1", {:-, :"$2", :"$3"}}}]}
    ])
    |> Map.new()
  end

  defp error_count(id) do
    @table
    |> :ets.select([
      {{{id, :_}, %{__struct__: Event, type: :"$1"}},
       [{:orelse, {:==, :"$1", :telemetry}, {:orelse, {:==, :"$1", :log}, {:==, :"$1", :exit}}}],
       [:"$_"]}
    ])
    |> Enum.count(fn {_key, event} -> Event.error?(event) end)
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
