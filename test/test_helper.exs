{:ok, _} = PhoenixReplay.Test.Endpoint.start_link()
# The Ecto storage is tested on SQLite, on DuckDB where QuackDB is a
# dependency, and on PostgreSQL when PHOENIX_REPLAY_POSTGRES_URL names one.
repos = PhoenixReplay.Test.Repos.start()

exclude =
  for {tag, repo} <- [
        postgres: PhoenixReplay.Test.PostgresRepo,
        duckdb: PhoenixReplay.Test.DuckDBRepo
      ],
      repo not in repos,
      do: tag

# Video export tests film real replays with Chromium and ffmpeg, so they
# run in `mix ci` and on CI, where `PHOENIX_REPLAY_EXPORT_TESTS` or `CI` is
# set, and only where both tools are there; a plain `mix test` skips them.
export_tests? =
  (System.get_env("PHOENIX_REPLAY_EXPORT_TESTS") || System.get_env("CI")) != nil and
    PhoenixReplay.Export.available(PhoenixReplay.Config.load()) == :ok

exclude = if export_tests?, do: exclude, else: [:export | exclude]

ExUnit.start(exclude: exclude)

# Dashboard TypeScript tests from priv/ts run as ExUnit tests: pure modules in
# QuickBEAM, DOM helpers and LiveView hooks in a browser against the real
# LiveView client.
Volt.Test.ExUnit.install(exclude: ["client/**", "dom/**", "hooks/**", "test/**"])

Volt.Test.ExUnit.install(
  include: ["client/**/*.test.ts", "dom/**/*.test.ts", "hooks/**/*.test.ts"],
  browser: true
)
