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
  persist: [attempts: 2, backoff: 0]

config :logger, level: :warning

config :volt, :test,
  root: "priv/ts",
  include: ["**/*.test.ts"],
  bundle: [resolve_dirs: ["deps"]]
