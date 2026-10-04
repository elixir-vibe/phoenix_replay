{:ok, _} = PhoenixReplay.Test.Endpoint.start_link()
# The Ecto storage runs on SQLite always, on DuckDB too, and on Postgres
# when PHOENIX_REPLAY_POSTGRES_URL names a database.
exclude = if System.get_env("PHOENIX_REPLAY_POSTGRES_URL"), do: [], else: [:postgres]
ExUnit.start(exclude: exclude)

# Dashboard TypeScript tests from priv/ts run as ExUnit tests: pure modules in
# QuickBEAM, DOM helpers and LiveView hooks in a browser against the real
# LiveView client.
Volt.Test.ExUnit.install(exclude: ["client/**", "dom/**", "hooks/**", "test/**"])

Volt.Test.ExUnit.install(
  include: ["client/**/*.test.ts", "dom/**/*.test.ts", "hooks/**/*.test.ts"],
  browser: true
)
