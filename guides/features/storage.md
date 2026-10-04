# Storage

In-progress sessions live in memory. When a session ends, it is saved through the configured storage backend, a `{module, opts}` tuple.

## Files

The default backend writes each recording as a compressed Erlang term file, plus a small summary file so listings never decode recordings:

```elixir
config :phoenix_replay,
  storage: {PhoenixReplay.Storage.File, path: "/var/lib/my_app/replays"}
```

The default `:path` is `"priv/replay_recordings"`, relative to the working directory. In a release, point it at a writable directory.

## Ecto

Store recordings in a table through your repo:

```elixir
config :phoenix_replay, storage: {PhoenixReplay.Storage.Ecto, repo: MyApp.Repo}
```

Create the table with a migration:

```elixir
defmodule MyApp.Repo.Migrations.CreatePhoenixReplayRecordings do
  use Ecto.Migration

  def change do
    create table(:phoenix_replay_recordings, primary_key: false) do
      add :id, :string, primary_key: true
      add :view, :string, null: false
      add :url, :text
      add :connected_at, :bigint, null: false
      add :event_count, :integer, null: false
      add :duration_ms, :integer, null: false
      add :error_count, :integer, null: false, default: 0
      add :event_names, :binary, null: false
      add :data, :binary, null: false
    end

    create index(:phoenix_replay_recordings, [:connected_at])
  end
end
```

## Running sessions

A running session is buffered in memory. With file storage, PhoenixReplay also writes it to disk in chunks while it runs, so its events leave memory however long it lasts, and a crash of the node loses at most the last few seconds:

```elixir
config :phoenix_replay,
  flush: [events: 200, interval: 5_000]
```

A chunk is written once a session has buffered `:events` events, or `:interval` milliseconds after its last one. Only sessions that will be kept are written, as `:keep` decides from the events seen so far; see [Telemetry and Logs](telemetry-and-logs.md#keeping-the-sessions-that-matter). Each chunk is redacted before it is written, so opening a running session in the dashboard only redacts the events since its last chunk. `flush: false` keeps sessions in memory until they end. `:flush` can be set per live session too.

Chunks are appended to `<id>.<node>.part` as checksummed frames. When the session ends, its chunks and remaining events are saved as one compressed recording, written to a temporary file, synced and renamed into place, and the part file is deleted. If the node stops first, the next start saves what was written as a recording ending in an `:exit` event that says it was interrupted. Nodes sharing a directory only recover their own part files.

A plain write survives a crash of the BEAM. To also survive losing power or the operating system, sync each chunk, at a cost per chunk:

```elixir
config :phoenix_replay,
  storage: {PhoenixReplay.Storage.File, path: "priv/replay_recordings", sync: true}
```

`PhoenixReplay.Storage.Ecto` saves each recording once, when it ends. A custom backend can take chunks by implementing the optional callbacks of `PhoenixReplay.Storage`.

When the application stops, it waits for recordings being saved or written.

## Retention

`PhoenixReplay.Recordings.Retention` deletes stored recordings older than `:max_age` milliseconds or beyond the newest `:max_count`, every `:interval` milliseconds:

```elixir
config :phoenix_replay,
  retention: [max_age: :timer.hours(24 * 7), max_count: 1_000, interval: :timer.minutes(10)]
```

Without `:max_age` or `:max_count`, recordings are kept until deleted from the dashboard.

## Format

Recordings are stored as compressed Erlang External Term Format, which keeps structs, atoms and tuples intact so templates re-render exactly. Decoding uses `:safe` mode: a recording that refers to atoms the node does not know, for example from a view that no longer exists, is skipped instead of creating atoms.

## Custom backends

Implement `PhoenixReplay.Storage`: `save/2`, `fetch/2`, `list/1`, `delete/2` and `clear/1`. `list/1` returns `PhoenixReplay.Recording.Summary` structs, most recent first, and should not decode full recordings. `PhoenixReplay.Storage.Codec` provides the encoding the built-in backends use.
