defmodule PhoenixReplay.MixProject do
  use Mix.Project

  @version "0.5.1"
  @source_url "https://github.com/elixir-vibe/phoenix_replay"

  def project do
    [
      app: :phoenix_replay,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers() ++ [:phoenix_iconify],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "PhoenixReplay",
      description: "Session recording and replay for Phoenix LiveView",
      source_url: @source_url,
      homepage_url: @source_url,
      dialyzer: [plt_add_apps: [:mix, :ex_unit, :ecto, :ecto_sql, :obscura]],
      aliases: aliases()
    ]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PhoenixReplay.Application, []},
      # The export endpoint takes its configuration as start options; Phoenix
      # warns about an endpoint without an entry here, so it has an empty one.
      env: [{PhoenixReplay.Web.Export.Endpoint, []}]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    duckdb() ++
      [
        {:phoenix_live_view, "~> 1.1"},
        {:telemetry, "~> 1.0"},
        {:ex2ms, "~> 1.7"},
        {:phoenix_iconify, "~> 0.3.7"},
        {:ua_parser, "~> 1.10"},
        # Highlights SQL and inspected Elixir terms in the player.
        {:lumis, "~> 0.10"},
        {:lumis_wasm_elixir, "~> 0.26.6"},
        {:lumis_wasm_sql, "~> 0.26.3"},
        {:lumis_wasm_comment, "~> 0.26.2"},
        {:ecto, "~> 3.12", optional: true},
        {:igniter, ">= 0.8.4 and < 1.0.0", optional: true},
        {:ecto_sql, "~> 3.12", optional: true},
        {:ecto_sqlite3, "~> 0.22", only: :test},
        {:postgrex, "~> 0.22", only: :test},
        {:jason, "~> 1.4", optional: true},
        {:obscura, "~> 0.2", optional: true},
        {:lazy_html, ">= 0.1.0", only: :test},
        # Captures replays for video export; see PhoenixReplay.Export.
        {:playwright_ex, "~> 0.14", optional: true},
        # Runs ffmpeg for video export, and stops it with the process that started it.
        {:muontrap, "~> 1.6 or ~> 2.0", optional: true},
        # Keeps video exports in the app's Oban queue; see PhoenixReplay.Export.Queue.Oban.
        {:oban, "~> 2.20", optional: true},
        {:bandit, "~> 1.5", only: :test},
        {:volt, "~> 0.22", only: [:dev, :test], runtime: false},
        {:ex_doc, "~> 0.35", only: :dev, runtime: false},
        {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
        {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
        {:reach, "~> 2.8", only: [:dev, :test], runtime: false}
      ]
  end

  # The Ecto storage and Oban export queue tests also run on DuckDB through
  # QuackDB and oban_quackdb, which need Elixir 1.19; the minimum-version CI
  # job skips them.
  defp duckdb do
    if Version.match?(System.version(), "~> 1.19"),
      do: [{:quackdb, "~> 0.5.28", only: :test}, {:oban_quackdb, "~> 0.1", only: :test}],
      else: []
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(
        lib
        priv/static/dashboard.js
        priv/static/dashboard.css
        priv/static/*.woff2
        priv/fonts/LICENSE
        priv/iconify/manifest.json
        priv/static/phoenix_replay.js
        priv/static/types
        package.json
        guides/**/*.md
        guides/**/*.cheatmd
        skills
        mix.exs
        .formatter.exs
        README.md
        CHANGELOG.md
        LICENSE
      )
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/introduction/getting-started.md",
        "guides/introduction/why-phoenix-replay.md",
        "guides/introduction/how-it-works.md",
        "guides/features/recording.md",
        "guides/features/live-components.md",
        "guides/features/telemetry-and-logs.md",
        "guides/features/dashboard.md",
        "guides/features/storage.md",
        "guides/features/privacy-and-security.md",
        "guides/cheatsheets/configuration.cheatmd"
      ],
      groups_for_extras: [
        Introduction: ~r/guides\/introduction\//,
        Features: ~r/guides\/features\//,
        Cheatsheets: ~r/guides\/cheatsheets\//
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      groups_for_modules: [
        Recording: [
          PhoenixReplay,
          PhoenixReplay.Recorder,
          PhoenixReplay.Replay,
          PhoenixReplay.Replay.View,
          PhoenixReplay.Migration,
          PhoenixReplay.Trace,
          PhoenixReplay.Plug,
          PhoenixReplay.Config,
          PhoenixReplay.Telemetry,
          PhoenixReplay.Recording,
          PhoenixReplay.Recording.Event,
          PhoenixReplay.Recording.Summary,
          PhoenixReplay.Recording.Filter,
          PhoenixReplay.Recording.Timeline,
          PhoenixReplay.Session.TailSampling,
          PhoenixReplay.Catalog,
          PhoenixReplay.Storage.Retention
        ],
        Collectors: ~r/^PhoenixReplay\.Collector/,
        "Video export": ~r/^PhoenixReplay\.Export/,
        Extension: [
          PhoenixReplay.Authorization,
          PhoenixReplay.Sanitizer,
          PhoenixReplay.Sanitizer.Default,
          PhoenixReplay.Redactor,
          PhoenixReplay.Redactor.Obscura,
          PhoenixReplay.Redactor.Patterns,
          PhoenixReplay.Storage,
          PhoenixReplay.Storage.Ecto,
          PhoenixReplay.Storage.Ecto.Migration,
          PhoenixReplay.Storage.File
        ],
        Dashboard: [PhoenixReplay.Router],
        "Mix Tasks": [Mix.Tasks.PhoenixReplay.Install],
        Capture: ~r/^PhoenixReplay\.Capture\./,
        Session: ~r/^PhoenixReplay\.Session\./,
        "Dashboard Internals": ~r/^PhoenixReplay\.Web\./,
        Internals: [PhoenixReplay.Application, PhoenixReplay.Storage.Codec]
      ]
    ]
  end

  # The client module host apps import, as an ES module with a stable name.
  # Mix runs a task once per invocation, so the second build is a rerun.
  defp build_client(_args) do
    Mix.Task.rerun("volt.build", [
      "--entry",
      "priv/ts/client/phoenix_replay.ts",
      "--format",
      "esm",
      "--name",
      "phoenix_replay"
    ])
  end

  # The gate runs the video export tests, which a plain `mix test` skips.
  defp export_tests(_args), do: System.put_env("PHOENIX_REPLAY_EXPORT_TESTS", "1")

  defp aliases do
    [
      "assets.build": [
        "volt.build --tailwind",
        &build_client/1,
        # The client's declarations, under the layout of priv/ts, which
        # package.json's types points into.
        "cmd rm -rf priv/static/types",
        "cmd npx tsc priv/ts/client/phoenix_replay.ts --declaration --emitDeclarationOnly --rootDir priv/ts --outDir priv/static/types --target es2022 --lib es2022,dom",
        "cmd rm -f priv/static/manifest.json"
      ],
      # The bundle in priv/static is not tracked, so every package builds it.
      # The build runs in its own mix process: compiling here would prune the
      # Hex archive from the code path before the Hex task runs.
      "hex.build": ["cmd mix assets.build", "hex.build"],
      "hex.publish": ["cmd mix assets.build", "hex.publish"],
      # Built in its own process, so this one compiles Web.Assets with it.
      ci: [
        &export_tests/1,
        "cmd mix assets.build",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "volt.js.check --type-aware --type-check",
        "test",
        "cmd elixir --sname phoenix_replay_ci -S mix test --only cluster",
        "credo --strict",
        "ex_dna --min-mass 20",
        "reach.check --arch --dead-code --smells --strict",
        "dialyzer",
        "deps.unlock --check-unused"
      ]
    ]
  end
end
