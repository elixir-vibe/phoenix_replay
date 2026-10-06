# Telemetry and Logs

A replay shows what the user did and what the view rendered. Collectors add what happened around it: the queries a click ran, the HTTP calls an async task made, the warnings a save logged. They appear in the player under the event that caused them, with their durations, and they can decide which sessions are kept.

## Collecting telemetry

List what to collect under `:collect`:

```elixir
config :phoenix_replay,
  collect: [
    {PhoenixReplay.Collector.Ecto, repo: MyApp.Repo},
    PhoenixReplay.Collector.Finch,
    [:my_app, :checkout, :stop]
  ]
```

Each entry is a `PhoenixReplay.Collector`, or an event name for the generic `PhoenixReplay.Collector.Generic`:

| Collector | Records |
|---|---|
| `PhoenixReplay.Collector.Ecto` | SQL, source, total, query, queue and decode times; failed queries as errors. Parameters only with `params: true`. |
| `PhoenixReplay.Collector.Finch` | Method and URL without the query string, status and duration; failed requests as errors. Covers Req, which uses Finch. |
| `PhoenixReplay.Collector.Generic` | Any event: its measurements and the metadata keys you choose. `:exception` events are errors. |

Collectors are attached when the application starts, so changing `:collect` takes a restart.

### Your own events

A bare event name records the event's measurements, with durations in milliseconds, and no metadata. Choose metadata, filter events and describe them with options borrowed from `Telemetry.Metrics`:

```elixir
config :phoenix_replay,
  collect: [
    {[:my_app, :search, :stop],
     metadata: [:query],
     keep: &(&1.results > 0),
     summary: &"search #{&1.query}"}
  ]
```

Functions in configuration must be defined in `config/runtime.exs` for releases. Otherwise write a collector module:

```elixir
defmodule MyApp.PaymentCollector do
  @behaviour PhoenixReplay.Collector

  alias PhoenixReplay.Collector
  alias PhoenixReplay.Collector.Captured

  @impl true
  def events(_opts), do: [[:my_app, :payment, :stop]]

  @impl true
  def capture(_event, measurements, metadata, _opts) do
    {:ok,
     %Captured{
       summary: "charge #{metadata.amount} #{metadata.currency}",
       measurements: Collector.milliseconds(measurements),
       metadata: Map.take(metadata, [:provider]),
       error: Collector.result_error(metadata.result)
     }}
  end
end
```

`capture/4` runs in the process that emitted the event, so keep it cheap and keep only the metadata a reader needs. Metadata often holds whole sockets, connections and structs.

### Marking moments

Analytics tools have custom events: "signed up", "checkout completed". In PhoenixReplay they are telemetry events too. Emit one where the moment happens:

```elixir
:telemetry.execute([:my_app, :checkout, :completed], %{amount: order.total}, %{plan: order.plan})
```

and collect it with `mark:` and the mark's name:

```elixir
config :phoenix_replay,
  collect: [
    {[:my_app, :checkout, :completed],
     metadata: [:plan], summary: &"checkout #{&1.plan}", mark: "Checkout completed"}
  ]
```

`mark: true` names the mark after the event, `"my_app.checkout.completed"`.

A mark is a moment, not work that took time. The player gives marks a lane of their own, flagged in the event list, and `M` and `Shift` + `M` jump between them. The recording list's **Mark** filter, and `PhoenixReplay.Trace.find(mark: "Checkout completed")`, find the sessions that reached one, with how many reached each. `keep: [marks: true]` saves every session with a mark; see [Keeping the sessions that matter](#keeping-the-sessions-that-matter).

Telemetry keeps your code free of PhoenixReplay: the same event can feed metrics, traces or an analytics handler. Like any collected event, a mark belongs to a session only when it is emitted in the LiveView's process or a task it started; see [Which session an event belongs to](#which-session-an-event-belongs-to). A collector module marks its events with `mark:` in `PhoenixReplay.Collector.Captured`.

## Collecting logs

```elixir
config :phoenix_replay, logs: [level: :info, metadata: [:request_id]]
```

PhoenixReplay adds a `:logger` handler that records messages at or above `:level`, formatted on one line, with the chosen metadata keys. Messages below Logger's own level are never emitted, so they are not recorded either.

## Which session an event belongs to

Telemetry handlers and `:logger` handlers run in the process that emitted the event or logged the message. An event belongs to the session of that process, or of the first of its `$callers` that is recorded. `Task` sets `$callers`, so this covers:

- queries and requests made by the LiveView itself, in any callback,
- `start_async/3`, `assign_async/3` and `stream_async/4` work, in the LiveView and its components,
- `Task.async/1` and `Task.Supervisor` tasks started from the LiveView.

Ecto runs queries in the calling process, so a query is attributed even though the connection lives in a pool. Work done in another process the LiveView calls, such as a `GenServer`, is not attributed. Events from processes outside recorded sessions cost one ETS lookup per process checked, and are dropped.

## Limits

Each collector records at most `:limit` events per session, `1_000` by default, and logs have their own `:limit`. Events beyond it are counted, not stored, and the player reports how many were dropped. Collected events do not count towards `:max_events`, so a chatty repo never crowds out the LiveView events a replay needs.

```elixir
config :phoenix_replay,
  collect: [{PhoenixReplay.Collector.Ecto, repo: MyApp.Repo, slower_than: 5, limit: 200}],
  logs: [level: :warning, limit: 100]
```

`:slower_than` on the Ecto and Finch collectors skips anything faster than that many milliseconds.

## Keeping the sessions that matter

Collected events can decide whether a session is saved. With tail sampling, every session is recorded, and when it ends only some are saved:

```elixir
config :phoenix_replay,
  keep: [rate: 0.05, errors: true, slower_than: 1_000],
  max_memory: 256 * 1024 * 1024
```

- `errors: true` always saves a session with an error log, a failed query or request, a telemetry `:exception` event, or a crash. A LiveView that exits abnormally gets an `:exit` event with the formatted reason.
- `slower_than: 1_000` always saves a session with a collected event that took at least a second.
- `marks: true` always saves a session with a [mark](#marking-moments), such as a completed checkout.
- `rate: 0.05` saves 5% of the remaining sessions with user interaction.

Each session is buffered until it ends, so set `:max_memory`. While the buffer is larger, new sessions are not recorded. `:keep` can be set per live session too:

```elixir
live_session :checkout,
  on_mount: [{PhoenixReplay.Recorder, keep: [rate: 1.0]}] do
  live "/checkout", CheckoutLive
end
```

The dashboard's **Errors** filter, or `?errors=1`, lists the sessions that had one.

## Redaction

Collected metadata goes through your `PhoenixReplay.Sanitizer`, like params. SQL, log messages and exit reasons are free text with no keys to filter, so they are masked when the session is saved, by a `PhoenixReplay.Redactor`. See [Privacy and Security](privacy-and-security.md#redacting-values).

## Failures

A collector that raises does not break your app or stop collecting: the event is skipped and `[:phoenix_replay, :collector, :exception]` is emitted with the collector, event, `kind`, `reason` and `stacktrace`. Attach a handler to it to find broken collectors.
