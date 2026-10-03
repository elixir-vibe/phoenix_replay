defmodule PhoenixReplay.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/elixir-vibe/phoenix_replay"

  def project do
    [
      app: :phoenix_replay,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "PhoenixReplay",
      description: "Session recording and replay for Phoenix LiveView",
      source_url: @source_url,
      homepage_url: @source_url,
      dialyzer: [plt_add_apps: [:mix, :ex_unit, :ecto, :obscura]],
      aliases: aliases()
    ]
  end

  def cli do
    [preferred_envs: [ci: :test, "assets.check": :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PhoenixReplay.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.1"},
      {:telemetry, "~> 1.0"},
      {:ecto, "~> 3.12", optional: true},
      {:igniter, ">= 0.8.4 and < 1.0.0", optional: true},
      {:ecto_sql, "~> 3.12", only: :test},
      {:ecto_sqlite3, "~> 0.22", only: :test},
      {:jason, "~> 1.4", optional: true},
      {:obscura, "~> 0.2", optional: true},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:playwright_ex, "~> 0.14", only: :test},
      {:volt, "~> 0.20", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(
        lib
        priv/static/dashboard.js
        priv/static/dashboard.css
        guides
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
          PhoenixReplay.Recording,
          PhoenixReplay.Recording.Event,
          PhoenixReplay.Recording.Keep,
          PhoenixReplay.Recording.Summary,
          PhoenixReplay.Recording.Timeline,
          PhoenixReplay.Recordings.Filter
        ],
        Collectors: [
          PhoenixReplay.Collector,
          PhoenixReplay.Collector.Captured,
          PhoenixReplay.Collector.Ecto,
          PhoenixReplay.Collector.Finch,
          PhoenixReplay.Collector.Telemetry
        ],
        Extension: [
          PhoenixReplay.Authorization,
          PhoenixReplay.Sanitizer,
          PhoenixReplay.Sanitizer.Default,
          PhoenixReplay.Redactor,
          PhoenixReplay.Redactor.Obscura,
          PhoenixReplay.Redactor.Patterns,
          PhoenixReplay.Storage,
          PhoenixReplay.Storage.Ecto,
          PhoenixReplay.Storage.File
        ],
        Dashboard: [PhoenixReplay.Router],
        "Mix Tasks": [Mix.Tasks.PhoenixReplay.Install],
        Internals: [
          PhoenixReplay.Application,
          PhoenixReplay.Config,
          PhoenixReplay.Recorder.AsyncComponents,
          PhoenixReplay.Recorder.Buffer,
          PhoenixReplay.Recorder.Collectors,
          PhoenixReplay.Recorder.Components,
          PhoenixReplay.Recorder.Flusher,
          PhoenixReplay.Recorder.Handlers,
          PhoenixReplay.Recorder.Logs,
          PhoenixReplay.Recorder.Monitor,
          PhoenixReplay.Recorder.Persister,
          PhoenixReplay.Recorder.Recovery,
          PhoenixReplay.Recordings,
          PhoenixReplay.Retention,
          PhoenixReplay.Storage.Codec,
          PhoenixReplay.Telemetry,
          PhoenixReplay.Web.Assets,
          PhoenixReplay.Web.Components,
          PhoenixReplay.Web.Context,
          PhoenixReplay.Web.Layouts,
          PhoenixReplay.Web.Live.Frame,
          PhoenixReplay.Web.Live.Index,
          PhoenixReplay.Web.Live.Show,
          PhoenixReplay.Web.Live.ReplayComponent,
          PhoenixReplay.Web.NotFoundError,
          PhoenixReplay.Web.Playback,
          PhoenixReplay.Web.Replay
        ]
      ]
    ]
  end

  defp aliases do
    [
      "assets.build": ["volt.build --tailwind", "cmd rm -f priv/static/manifest.json"],
      "assets.check": [
        "assets.build",
        "cmd git diff --exit-code -- priv/static/dashboard.js priv/static/dashboard.css"
      ],
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "volt.js.check --type-aware --type-check",
        "assets.check",
        "test",
        "credo --strict",
        "ex_dna --min-mass 20",
        "reach.check --arch --dead-code --smells --strict",
        "dialyzer",
        "deps.unlock --check-unused"
      ]
    ]
  end
end
