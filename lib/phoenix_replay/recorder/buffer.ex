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
    * `{{id, :state}, draw, flushed}` — the session's draw for
      `keep: [rate: ...]`, made when it opens, and totals of the events
      already flushed to storage, written only by the process flushing it
    * `{{id, seq}, event}` — one per event not yet flushed, `seq` counting
      up from `0`

  Integer keys sort before atoms, so each session's events precede its
  metadata rows in the ordered set.
  """

  import Ex2ms

  alias PhoenixReplay.{Config, Storage}
  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Event, Summary}

  @table __MODULE__

  @typedoc "Totals of the events a session has flushed to storage."
  @type flushed :: %{
          event_count: non_neg_integer(),
          error_count: non_neg_integer(),
          event_names: [String.t()],
          duration_ms: non_neg_integer()
        }

  @no_flushed %{event_count: 0, error_count: 0, event_names: [], duration_ms: 0}

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
  @spec open(Recording.t(), pid(), Config.t(), float()) :: :ok
  def open(%Recording{id: id} = recording, pid, %Config{} = config, draw \\ :rand.uniform()) do
    :ets.insert(@table, [
      {{id, :meta}, pid, config, %{recording | events: []}},
      {{id, :seq}, 0, 0},
      {{id, :state}, draw, @no_flushed},
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

  @doc "Returns the session's recording without its events."
  @spec meta(Recording.id()) :: {:ok, Recording.t()} | :error
  def meta(id) do
    case :ets.lookup(@table, {id, :meta}) do
      [{_key, _pid, _config, recording}] -> {:ok, %{recording | dropped: dropped(id)}}
      [] -> :error
    end
  end

  @doc "Counts the session's buffered events."
  @spec pending_count(Recording.id()) :: non_neg_integer()
  def pending_count(id), do: event_count(id)

  @doc "Returns the session's draw for `keep: [rate: ...]`, made when it opened."
  @spec draw(Recording.id()) :: {:ok, float()} | :error
  def draw(id) do
    case :ets.lookup(@table, {id, :state}) do
      [{_key, draw, _flushed}] -> {:ok, draw}
      [] -> :error
    end
  end

  @doc "Returns true once some of the session's events were flushed to storage."
  @spec flushed?(Recording.id()) :: boolean()
  def flushed?(id) do
    match?(
      [{_key, _draw, %{event_count: count}}] when count > 0,
      :ets.lookup(@table, {id, :state})
    )
  end

  @doc """
  Returns the session's buffered events with their sequence numbers, in
  order. Events written concurrently may still arrive with lower numbers;
  they are returned by a later call.
  """
  @spec pending(Recording.id(), integer()) :: Storage.chunk()
  def pending(id, after_seq \\ -1) do
    :ets.select(
      @table,
      fun do
        {{^id, seq}, event} when is_integer(seq) and seq > ^after_seq -> {seq, event}
      end
    )
  end

  @doc """
  Removes events written to storage by the session's flusher, and adds
  them to its flushed totals.
  """
  @spec flushed(Recording.id(), Storage.chunk()) :: :ok
  def flushed(id, chunk) do
    [{key, draw, totals}] = :ets.lookup(@table, {id, :state})
    events = Enum.map(chunk, fn {_seq, event} -> event end)

    totals = %{
      event_count: totals.event_count + length(events),
      error_count: totals.error_count + Enum.count(events, &Event.error?/1),
      event_names: Enum.sort(Enum.uniq(totals.event_names ++ Summary.event_names(events))),
      duration_ms: Enum.reduce(events, totals.duration_ms, &max(&1.at, &2))
    }

    :ets.insert(@table, {key, draw, totals})
    Enum.each(chunk, fn {seq, _event} -> :ets.delete(@table, {id, seq}) end)
  end

  @doc """
  Returns the session's buffered recording. Events already flushed to
  storage are not included; see `flushed?/1`.
  """
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
    :ets.select(@table, fun(do: ({{id, :meta}, pid, _config, _recording} -> {id, pid})))
  end

  @doc "Summarizes every buffered session, most recent first."
  @spec summaries() :: [Summary.t()]
  def summaries do
    @table
    |> :ets.select(fun(do: ({{_id, :meta}, pid, _config, recording} -> {pid, recording})))
    |> Enum.map(fn {pid, recording} ->
      flushed = flushed_totals(recording.id)

      %{
        Summary.new(recording, live?: Process.alive?(pid))
        | event_count: flushed.event_count + event_count(recording.id),
          event_names: Enum.sort(Enum.uniq(flushed.event_names ++ event_names(recording.id))),
          error_count: flushed.error_count + error_count(recording.id),
          duration_ms: max(flushed.duration_ms, duration_ms(recording.id))
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
    :ets.delete(@table, {id, :state})
    :ets.delete(@table, {id, :meta})
    :ets.select_delete(@table, events_of(id))
    :ok
  end

  defp flushed_totals(id) do
    case :ets.lookup(@table, {id, :state}) do
      [{_key, _draw, totals}] -> totals
      [] -> @no_flushed
    end
  end

  defp write(id, started_at, type, data) do
    seq = :ets.update_counter(@table, {id, :seq}, {2, 1}) - 1
    at = System.monotonic_time(:millisecond) - started_at
    append(id, seq, %Event{at: at, type: type, data: data})
  end

  # Rows of the session's buffered events, which have integer sequence keys.
  defp events_of(id), do: fun(do: ({{^id, seq}, _event} when is_integer(seq) -> true))

  defp events(id) do
    :ets.select(@table, fun(do: ({{^id, seq}, event} when is_integer(seq) -> event)))
  end

  defp event_count(id) do
    :ets.select_count(@table, events_of(id))
  end

  defp event_names(id) do
    @table
    |> :ets.select(fun(do: ({{^id, _seq}, %{type: :event, data: %{name: name}}} -> name)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp dropped(id) do
    @table
    |> :ets.select(
      fun do
        {{:collected, ^id, name}, count, limit} when count > limit -> {name, count - limit}
      end
    )
    |> Map.new()
  end

  defp error_count(id) do
    @table
    |> :ets.select(
      fun do
        {{^id, _seq}, %{type: type}} = row
        when type == :telemetry or type == :log or type == :exit ->
          row
      end
    )
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
