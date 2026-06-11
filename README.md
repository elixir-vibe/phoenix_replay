# PhoenixReplay

Session recording and replay for Phoenix LiveView.

![PhoenixReplay dashboard replaying a form session](screenshot.jpg)

LiveView templates are pure functions: same assigns produce the same HTML. PhoenixReplay captures assigns at each state transition and replays them by re-rendering the original view — no client-side recording, no DOM snapshots, no JavaScript changes. A 30-second session with active form input is ~400 events and ~8 KB on disk (ETF + gzip).

## Quick start

Add the dependency:

```elixir
def deps do
  [{:phoenix_replay, "~> 0.1.0"}]
end
```

Attach the recorder to a live session:

```elixir
live_session :default, on_mount: [PhoenixReplay.Recorder] do
  live "/dashboard", DashboardLive
  live "/posts", PostLive.Index
end
```

Mount the replay dashboard:

```elixir
import PhoenixReplay.Router

scope "/" do
  pipe_through [:browser, :require_admin]
  phoenix_replay "/replay"
end
```

Visit `/replay` to browse recordings and replay sessions with a scrubber, play/pause, and speed controls. Every connected LiveView in the live session is recorded automatically — sanitized mount params, events, navigation, and assign deltas. Sessions with no user interaction are discarded.

Recordings can contain business data even after sanitization. Mount the dashboard only behind an authenticated admin pipeline. You can also add a final authorization callback:

```elixir
config :phoenix_replay,
  authorize: fn recording -> recording.view in [MyAppWeb.SafeLive] end
```

## How it works

1. The `on_mount` hook attaches lifecycle hooks to each connected LiveView.
2. Session start sends a single async cast to the Store GenServer to set up a process monitor.
3. All subsequent events are written directly to ETS (`ordered_set` with `write_concurrency`) — no GenServer messages on the hot path.
4. When the LiveView process exits, the Store finalizes the recording and hands persistence to a supervised worker.

### Recorded events

| Event | Data |
|---|---|
| Mount | View module, URL, params, session, initial assigns |
| Handle event | Event name, params |
| Handle params | URL, params |
| Handle info | Type marker only |
| After render | Changed assigns (delta, or full snapshot when batched) |

Each event includes a millisecond offset from session start.

### Current limitations

Replay is currently based on root LiveView assigns. It does not fully reconstruct stateful LiveComponents, streams, uploads, client-only JavaScript state, or pushed JS events. Those sessions may still be useful for debugging server-side state, but replay output can differ from what the browser showed.

## Configuration

```elixir
config :phoenix_replay,
  max_events: 10_000,
  sanitizer: MyApp.ReplaySanitizer,
  max_recordings: 1_000,
  max_recording_age_ms: 7 * 24 * 60 * 60 * 1000,
  cleanup_interval_ms: 60 * 60 * 1000,
  persistence_retry_attempts: 3,
  persistence_retry_delay_ms: 1_000
```

### Storage backends

Active recordings live in ETS. When a LiveView process exits, the recording is persisted via the configured backend. Async persistence retries transient failures using `:persistence_retry_attempts` and `:persistence_retry_delay_ms`; cleanup can be limited by `:max_recordings`, `:max_recording_age_ms`, and `:cleanup_interval_ms`.

**File (default):**

```elixir
config :phoenix_replay,
  storage: PhoenixReplay.Storage.File,
  storage_opts: [path: "priv/replay_recordings", format: :etf]
```

**Ecto:**

```elixir
config :phoenix_replay,
  storage: PhoenixReplay.Storage.Ecto,
  storage_opts: [repo: MyApp.Repo, format: :etf]
```

Requires a migration:

```elixir
defmodule MyApp.Repo.Migrations.CreatePhoenixReplayRecordings do
  use Ecto.Migration

  def change do
    create table(:phoenix_replay_recordings, primary_key: false) do
      add :id, :string, primary_key: true
      add :view, :string, null: false
      add :connected_at, :bigint, null: false
      add :event_count, :integer, null: false, default: 0
      add :data, :binary, null: false
      timestamps(type: :utc_datetime)
    end
  end
end
```

Both backends support `:etf` (default — fast, preserves Elixir types) and `:json` (portable but lossy).

### Custom sanitizer

The default sanitizer strips internal LiveView keys and sensitive fields, and compacts `Form`, `Changeset`, and Ecto structs. To customize:

```elixir
defmodule MyApp.ReplaySanitizer do
  @drop [:__changed__, :flash, :uploads, :streams,
         :_replay_id, :_replay_t0, :csrf_token, :password,
         :current_password, :password_confirmation, :token, :secret,
         :my_custom_secret]

  def sanitize_assigns(assigns), do: Map.drop(assigns, @drop)
  def sanitize_params(params), do: Map.drop(params, Enum.map(@drop, &Atom.to_string/1))

  def sanitize_delta(changed, assigns) do
    changed
    |> Map.keys()
    |> Enum.reject(&(&1 in @drop))
    |> Map.new(fn key -> {key, Map.get(assigns, key)} end)
  end
end
```

## Manual attachment

To record individual views instead of an entire live session:

```elixir
def mount(params, session, socket) do
  {:ok, PhoenixReplay.Recorder.attach(socket, params, session)}
end
```

## Programmatic access

```elixir
PhoenixReplay.Store.list_recording_summaries()
PhoenixReplay.Store.list_recordings()
PhoenixReplay.Store.get_recording(id)
PhoenixReplay.Store.get_active(id)
PhoenixReplay.Store.delete_recording(id)
PhoenixReplay.Store.clear_all()
PhoenixReplay.Store.cleanup()
```

## Roadmap

- Real-time session observation via PubSub
- LiveComponent state tracking
- Configurable sampling (record N% of sessions)
- Session search and filtering

## Part of Elixir Vibe

PhoenixReplay records LiveView sessions as assigns timelines, making every session replayable and every bug reproducible.

It is one building block of a larger stack — tools that make AI-generated
software checkable: structural search, dependence analysis, duplication and
slop detection, session replay, and ecosystem-wide code search. See the
[Elixir Vibe](https://github.com/elixir-vibe) organization for the rest, and
[Building Blocks for the Future Web](https://github.com/elixir-vibe/building-blocks)
for the thesis, architecture, and roadmap that tie them together.

## License

MIT
