import Config

config :phoenix, :json_library, Jason

config :phoenix_replay, PhoenixReplay.Test.Endpoint,
  http: [port: 4002],
  server: false,
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "test_salt"],
  render_errors: [formats: [html: PhoenixReplay.Test.ErrorHTML], layout: false]

config :phoenix_replay,
  storage:
    {PhoenixReplay.Storage.File, path: Path.join(System.tmp_dir!(), "phoenix_replay_test")},
  persist: [attempts: 2, backoff: 0],
  # Tests flush sessions explicitly, so no chunk is written behind their backs.
  flush: false

config :logger, level: :warning

config :volt, :test,
  root: "priv/ts",
  include: ["**/*.test.ts"],
  bundle: [resolve_dirs: ["deps"]]

# Repos the Ecto storage is tested on; see test/support/repos.ex. Each test
# runs in a sandboxed transaction.
config :phoenix_replay, PhoenixReplay.Test.SQLiteRepo,
  database: "tmp/test/replay.sqlite3",
  pool: Ecto.Adapters.SQL.Sandbox,
  # SQLite allows one writer, so more connections only wait on its lock.
  pool_size: 1,
  # Connections switching a new database to WAL at once lock each other out.
  journal_mode: :delete,
  log: false

config :phoenix_replay, PhoenixReplay.Test.PostgresRepo,
  url: System.get_env("PHOENIX_REPLAY_POSTGRES_URL"),
  pool: Ecto.Adapters.SQL.Sandbox,
  log: false

config :phoenix_replay, PhoenixReplay.Test.DuckDBRepo,
  pool: Ecto.Adapters.SQL.Sandbox,
  log: false
