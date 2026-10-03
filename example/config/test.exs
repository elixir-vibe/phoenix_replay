import Config

config :example, Example.Repo,
  database: Path.expand("../example_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :example, ExampleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "lDrxv1MMVskqUmho9J3CdnQMSK36KlJA58zgNsuoOGoeA0fsgniUAUrlL2+7NmTx",
  server: true

config :example, sql_sandbox: true

config :phoenix_replay,
  storage:
    {PhoenixReplay.Storage.File,
     path: Path.join(System.tmp_dir!(), "phoenix_replay_example_test")}

config :phoenix_test,
  otp_app: :example,
  playwright: [timeout: 5_000]

config :example, Example.Repo, pool: Ecto.Adapters.SQL.Sandbox

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
