defmodule PhoenixReplay.Session.Buffer do
  @moduledoc """
  ETS buffer for in-progress recordings.

  The recorded LiveView process writes its own events straight into the
  table, so recording never waits on another process. Events from the view,
  its LiveComponents and its collectors share one counter, so they stay in
  order. The table is created by `PhoenixReplay.Application` and outlives
  every worker, which lets `PhoenixReplay.Session.Monitor` recover sessions
  after a restart.

  The session's summary totals are kept as events are written, with
  `PhoenixReplay.Recording.Summary.counts/1`, so listing running sessions
  never reads their events.

  Rows:

    * `{{id, :meta}, pid, recording}` — one per session
    * `{{id, :config}, config}` — the configuration the session records with
    * `{{id, :seq}, seq, live, bytes, flushed, shown, errors}` — events
      stored so far, LiveView events seen so far including those beyond
      `:max_events`, the external size of the events still buffered, which
      `memory/0` counts, the events flushed to storage, and the events and
      errors a summary counts
    * `{{id, :last_at}, at}` — the latest offset among flushed events,
      written only by the process flushing it
    * `{{:event_name, id, name}}` — one per `handle_event/3` name seen
    * `{{:mark, id, name}, count}` — how many times each mark was reached
    * `{{:process, pid}, id, started_at, max_events, sanitizer, media}` —
      finds the session of the calling process, with what recording an
      event needs, small enough to read on every event: `media` lists the
      media settings the `:client` config keeps
    * `{{:collected, id, name}, count, limit}` — events a collector captured
      for the session, including those beyond its `:limit`
    * `{{id, :state}, draw}` — the session's draw for `keep: [rate: ...]`,
      made when it opens
    * `{{id, seq}, event}` — one per event not yet flushed, `seq` counting
      up from `0`
    * `{{id, :saving}, true}` — the session ended and a task is saving it
  """

  import Ex2ms

  alias PhoenixReplay.{Config, Storage}
  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Event, Summary}

  @table __MODULE__

  @typedoc "A buffered session found by `attribute/1`."
  @opaque session :: {Recording.id(), integer()}

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
      {{id, :meta}, pid, %{recording | events: []}},
      {{id, :config}, config},
      {{id, :seq}, 0, 0, 0, 0, 0, 0},
      {{id, :last_at}, 0},
      {{id, :state}, draw},
      {{:process, pid}, id, System.monotonic_time(:millisecond), config.max_events,
       config.sanitizer, config.client.media}
    ])

    :ok
  end

  @doc "Returns the id and the sanitizer of the session `pid` records, if any."
  @spec session(pid()) :: {:ok, Recording.id(), module()} | :error
  def session(pid) do
    case :ets.lookup(@table, {:process, pid}) do
      [{_key, id, _started_at, _max_events, sanitizer, _media}] -> {:ok, id, sanitizer}
      [] -> :error
    end
  end

  @doc """
  The media settings the session `pid` records keeps, from the `:client`
  config, if it records one.
  """
  @spec media(pid()) :: {:ok, [Config.media()]} | :error
  def media(pid) do
    case :ets.lookup(@table, {:process, pid}) do
      [{_key, _id, _started_at, _max_events, _sanitizer, media}] -> {:ok, media}
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
      [{_key, id, started_at, max_events, _sanitizer, _media}] ->
        if :ets.update_counter(@table, {id, :seq}, {3, 1}) <= max_events,
          do: write(id, started_at, type, data),
          else: :full

      [] ->
        :error
    end
  end

  @doc """
  Finds the session recorded by the first of `pids` that records one, and
  its sanitizer.

  Collectors pass the emitting process followed by its `$callers`, so
  events from tasks a LiveView started belong to its session.
  """
  @spec attribute([pid()]) :: {:ok, session(), module()} | :error
  def attribute([]), do: :error

  def attribute([pid | rest]) do
    case :ets.lookup(@table, {:process, pid}) do
      [{_key, id, started_at, _max_events, sanitizer, _media}] ->
        {:ok, {id, started_at}, sanitizer}

      [] ->
        attribute(rest)
    end
  end

  @doc """
  Appends a collected event to a session found by `attribute/1`.

  Events are counted per collector `name`; once `limit` is reached they
  are counted but not stored, and `fetch/1` reports them as dropped.
  Collected events do not count towards `:max_events`.
  """
  @spec collect(session(), Event.type(), map(), String.t(), pos_integer()) :: :ok | :dropped
  def collect({id, started_at}, type, data, name, limit) do
    key = {:collected, id, name}

    if :ets.update_counter(@table, key, {2, 1}, {key, 0, limit}) <= limit,
      do: write(id, started_at, type, data),
      else: :dropped
  end

  @doc """
  Approximate memory used by every buffered session, in bytes: the table
  itself, and the events' sizes, since ETS counts binaries larger than 64
  bytes, such as SQL, log messages and long strings, only by reference.
  """
  @spec memory() :: non_neg_integer()
  def memory do
    events =
      :ets.select(
        @table,
        fun(do: ({{_id, :seq}, _seq, _live, bytes, _flushed, _shown, _errors} -> bytes))
      )

    :ets.info(@table, :memory) * :erlang.system_info(:wordsize) + Enum.sum(events)
  end

  @doc "Sets the session's URL. Only the recording process writes its metadata row."
  @spec put_url(Recording.id(), String.t()) :: :ok
  def put_url(id, url), do: update_recording(id, &%{&1 | url: url})

  @doc "Sets the layout the session's view renders in; see `PhoenixReplay.Recording`."
  @spec put_layout(Recording.id(), Recording.layout()) :: :ok
  def put_layout(id, layout), do: update_recording(id, &%{&1 | layout: layout})

  defp update_recording(id, fun) do
    case :ets.lookup(@table, {id, :meta}) do
      [{key, pid, recording}] ->
        :ets.insert(@table, {key, pid, fun.(recording)})

      [] ->
        :ok
    end

    :ok
  end

  @doc "Stores the event with sequence number `seq`, as `record/3` does."
  @spec append(Recording.id(), non_neg_integer(), Event.t()) :: :ok
  def append(id, seq, %Event{} = event) do
    :ets.insert(@table, {{id, seq}, event})
    {shown, error, _name, _mark} = count(id, event)
    :ets.update_counter(@table, {id, :seq}, [{6, shown}, {7, error}])
    :ok
  end

  @doc "Returns the session's recording without its events."
  @spec meta(Recording.id()) :: {:ok, Recording.t()} | :error
  def meta(id) do
    case :ets.lookup(@table, {id, :meta}) do
      [{_key, _pid, recording}] -> {:ok, %{recording | dropped: dropped(id)}}
      [] -> :error
    end
  end

  @doc """
  Counts the session's buffered events from its counters, without reading
  them. An event being written concurrently may already be counted.
  """
  @spec pending_count(Recording.id()) :: non_neg_integer()
  def pending_count(id) do
    case :ets.lookup(@table, {id, :seq}) do
      [{_key, seq, _live, _bytes, flushed, _shown, _errors}] -> seq - flushed
      [] -> 0
    end
  end

  @doc "Returns the session's draw for `keep: [rate: ...]`, made when it opened."
  @spec draw(Recording.id()) :: {:ok, float()} | :error
  def draw(id) do
    case :ets.lookup(@table, {id, :state}) do
      [{_key, draw}] -> {:ok, draw}
      [] -> :error
    end
  end

  @doc "Returns true once some of the session's events were flushed to storage."
  @spec flushed?(Recording.id()) :: boolean()
  def flushed?(id) do
    match?(
      [{_key, _seq, _live, _bytes, flushed, _shown, _errors}] when flushed > 0,
      :ets.lookup(@table, {id, :seq})
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
  Removes events written to storage by the session's flusher. They stay
  counted in its summary.
  """
  @spec remove_flushed(Recording.id(), Storage.chunk()) :: :ok
  def remove_flushed(id, chunk) do
    Enum.each(chunk, fn {seq, _event} -> :ets.delete(@table, {id, seq}) end)
    bytes = Enum.sum_by(chunk, fn {_seq, event} -> :erlang.external_size(event) end)
    last_at = Enum.reduce(chunk, 0, fn {_seq, event}, acc -> max(event.at, acc) end)

    :ets.insert(
      @table,
      {{id, :last_at}, max(last_at, :ets.lookup_element(@table, {id, :last_at}, 2, 0))}
    )

    try do
      :ets.update_counter(@table, {id, :seq}, [{4, -bytes}, {5, length(chunk)}])
      :ok
    rescue
      # The session closed while its chunk was written.
      ArgumentError -> :ok
    end
  end

  @doc """
  Returns the session's buffered recording. Events already flushed to
  storage are not included; see `flushed?/1`.
  """
  @spec fetch(Recording.id()) :: {:ok, Recording.t()} | :error
  def fetch(id) do
    case :ets.lookup(@table, {id, :meta}) do
      [{_key, _pid, recording}] ->
        {:ok, %{recording | events: events(id), dropped: dropped(id)}}

      [] ->
        :error
    end
  end

  @doc "Returns the configuration the session was started with."
  @spec config(Recording.id()) :: {:ok, Config.t()} | :error
  def config(id) do
    case :ets.lookup(@table, {id, :config}) do
      [{_key, config}] -> {:ok, config}
      [] -> :error
    end
  end

  @doc "Lists `{id, pid}` for every buffered session not already being saved."
  @spec sessions() :: [{Recording.id(), pid()}]
  def sessions do
    @table
    |> :ets.select(fun(do: ({{id, :meta}, pid, _recording} -> {id, pid})))
    |> Enum.reject(fn {id, _pid} -> :ets.member(@table, {id, :saving}) end)
  end

  @doc """
  Marks the session as being saved, so a restarted
  `PhoenixReplay.Session.Monitor` leaves it to the task saving it.
  """
  @spec mark_saving(Recording.id()) :: :ok
  def mark_saving(id) do
    :ets.insert(@table, {{id, :saving}, true})
    :ok
  end

  @doc """
  Summarizes every buffered session, most recent first, counting the
  events flushed to storage and those still buffered from the session's
  running totals.
  """
  @spec summaries() :: [Summary.t()]
  def summaries do
    @table
    |> :ets.select(fun(do: ({{_id, :meta}, pid, recording} -> {pid, recording})))
    |> Enum.map(fn {pid, recording} ->
      struct!(Summary.new(recording, live?: Process.alive?(pid)), totals(recording.id))
    end)
    |> Summary.sort()
  end

  @doc "Removes the session and all of its events."
  @spec close(Recording.id()) :: :ok
  def close(id) do
    :ets.match_delete(@table, {{:process, :_}, id, :_, :_, :_, :_})
    :ets.match_delete(@table, {{:collected, id, :_}, :_, :_})
    :ets.match_delete(@table, {{:event_name, id, :_}})
    :ets.match_delete(@table, {{:mark, id, :_}, :_})
    :ets.delete(@table, {id, :seq})
    :ets.delete(@table, {id, :last_at})
    :ets.delete(@table, {id, :state})
    :ets.delete(@table, {id, :saving})
    :ets.delete(@table, {id, :config})
    :ets.delete(@table, {id, :meta})
    :ets.select_delete(@table, events_of(id))
    :ok
  end

  defp totals(id) do
    case :ets.lookup(@table, {id, :seq}) do
      [{_key, _seq, _live, _bytes, _flushed, shown, errors}] ->
        %{
          event_count: shown,
          error_count: errors,
          event_names: :ets.select(@table, fun(do: ({{:event_name, ^id, name}} -> name))),
          marks: Map.new(:ets.select(@table, fun(do: ({{:mark, ^id, name}, n} -> {name, n})))),
          duration_ms:
            max(:ets.lookup_element(@table, {id, :last_at}, 2, 0), last_buffered_at(id))
        }

      [] ->
        Summary.totals([])
    end
  end

  defp write(id, started_at, type, data) do
    at = System.monotonic_time(:millisecond) - started_at
    event = %Event{at: at, type: type, data: data}
    {shown, error, _name, _mark} = count(id, event)

    [next | _counts] =
      :ets.update_counter(@table, {id, :seq}, [
        {2, 1},
        {4, :erlang.external_size(event)},
        {6, shown},
        {7, error}
      ])

    :ets.insert(@table, {{id, next - 1}, event})

    # The session may close between the counter and the insert; nothing it
    # leaves behind would ever be removed.
    if :ets.member(@table, {id, :meta}), do: :ok, else: discard(id, next - 1)
  rescue
    # It closed before the counter: its rows are already gone.
    ArgumentError -> discard(id, nil)
  end

  # Notes the event's name and mark for the session's totals, and returns
  # what it adds to the counters.
  defp count(id, event) do
    {_shown, _error, name, mark} = counts = Summary.counts(event)
    if name, do: :ets.insert(@table, {{:event_name, id, name}})
    if mark, do: :ets.update_counter(@table, {:mark, id, mark}, 1, {{:mark, id, mark}, 0})
    counts
  end

  # Integer keys sort before atoms, and the empty atom before every other
  # atom, so the row before `{id, :""}` is the session's most recent
  # buffered event, if any, whatever atom keys the session has.
  defp last_buffered_at(id) do
    with {^id, seq} when is_integer(seq) <- :ets.prev(@table, {id, :""}),
         [{_key, %Event{at: at}}] <- :ets.lookup(@table, {id, seq}) do
      at
    else
      _none -> 0
    end
  end

  defp discard(id, seq) do
    if seq, do: :ets.delete(@table, {id, seq})
    :ets.match_delete(@table, {{:collected, id, :_}, :_, :_})
    :ets.match_delete(@table, {{:event_name, id, :_}})
    :ets.match_delete(@table, {{:mark, id, :_}, :_})
    :ok
  end

  # Rows of the session's buffered events, which have integer sequence keys.
  defp events_of(id), do: fun(do: ({{^id, seq}, _event} when is_integer(seq) -> true))

  defp events(id) do
    :ets.select(@table, fun(do: ({{^id, seq}, event} when is_integer(seq) -> event)))
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
end
