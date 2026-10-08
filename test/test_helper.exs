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

# Tests across nodes start a peer, which needs a distributed VM: `mix ci`
# runs them with `elixir --sname ... -S mix test --only cluster`.
exclude = if Node.alive?(), do: exclude, else: [:cluster | exclude]

ExUnit.start(exclude: exclude)

# Dashboard TypeScript tests from priv/ts run as ExUnit tests: pure modules in
# QuickBEAM, DOM helpers and LiveView hooks in a browser against the real
# LiveView client. The browser runs under Volt's own supervisor, and Volt is
# a build-time dependency, so its application is started here.
{:ok, _apps} = Application.ensure_all_started(:volt)
Volt.Test.ExUnit.install(exclude: ["client/**", "replay/**", "dashboard/**", "test/**"])

Volt.Test.ExUnit.install(
  include: ["client/**/*.test.ts", "replay/**/*.test.ts", "dashboard/**/*.test.ts"],
  browser: true
)
