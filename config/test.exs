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
  flush: false,
  # Visits end 50 ms after their last recording, so a session held for its
  # visit's decision is decided while the test awaits it.
  client: [landing: [timeout: 50]],
  # Small, quick videos; the tests tagged :export need ffmpeg and Playwright.
  export: [
    endpoint: PhoenixReplay.Test.Endpoint,
    dir: Path.join(System.tmp_dir!(), "phoenix_replay_test_exports"),
    playwright: [executable: "node_modules/.bin/playwright"],
    fps: 10,
    max_dpr: 1,
    hold: 500
  ]

config :logger, level: :warning

config :volt, :test,
  root: "priv/ts",
  include: ["**/*.test.ts"],
  # @sinonjs/fake-timers requires Node's timers/promises, which its
  # package maps to nothing in browsers; Volt does not read that mapping.
  bundle: [resolve_dirs: ["deps"], external: ["timers/promises"]]

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
