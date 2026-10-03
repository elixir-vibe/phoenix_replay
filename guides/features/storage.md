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
      add :event_names, :binary, null: false
      add :data, :binary, null: false
    end

    create index(:phoenix_replay_recordings, [:connected_at])
  end
end
```

## Retention

`PhoenixReplay.Retention` deletes stored recordings older than `:max_age` milliseconds or beyond the newest `:max_count`, every `:interval` milliseconds:

```elixir
config :phoenix_replay,
  retention: [max_age: :timer.hours(24 * 7), max_count: 1_000, interval: :timer.minutes(10)]
```

Without `:max_age` or `:max_count`, recordings are kept until deleted from the dashboard.

## Format

Recordings are stored as compressed Erlang External Term Format, which keeps structs, atoms and tuples intact so templates re-render exactly. Decoding uses `:safe` mode: a recording that refers to atoms the node does not know, for example from a view that no longer exists, is skipped instead of creating atoms.

## Custom backends

Implement `PhoenixReplay.Storage`: `save/2`, `fetch/2`, `list/1`, `delete/2` and `clear/1`. `list/1` returns `PhoenixReplay.Recording.Summary` structs, most recent first, and should not decode full recordings. `PhoenixReplay.Storage.Codec` provides the encoding the built-in backends use.
