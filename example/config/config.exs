# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :volt,
  entry: "assets/js/app.ts",
  outdir: "priv/static/assets",
  # LiveView writes colocated hooks under the build path ("phoenix-colocated/example").
  resolve_dirs: ["deps", Mix.Project.build_path()],
  target: :es2020,
  sourcemap: :hidden,
  tailwind: [
    css: "assets/css/app.css",
    sources: [
      %{base: "lib/", pattern: "**/*.{ex,heex}"},
      %{base: "assets/", pattern: "**/*.{js,ts,jsx,tsx}"}
    ]
  ],
  lint: [
    tsgolint: "assets/node_modules/.bin/tsgolint",
    plugins: ["typescript", "import", "unicorn"],
    rules: %{
      "no-debugger" => :deny,
      "no-unused-vars" => :warn,
      "no-console" => :warn,
      "no-empty-function" => :deny,
      "eqeqeq" => :deny,
      "no-var" => :deny,
      "prefer-const" => :deny,
      "typescript/no-explicit-any" => :warn,
      "typescript/no-non-null-assertion" => :warn,
      "typescript/consistent-type-imports" => :deny,
      "typescript/no-floating-promises" => :deny,
      "typescript/no-misused-promises" => :deny,
      "import/no-cycle" => :deny,
      "import/no-self-import" => :deny,
      "import/no-duplicates" => :deny,
      "import/no-mutable-exports" => :deny,
      "unicorn/no-instanceof-array" => :deny,
      "unicorn/no-typeof-undefined" => :deny,
      "unicorn/no-nested-ternary" => :deny,
      "unicorn/no-useless-fallback-in-spread" => :deny,
      "unicorn/no-unnecessary-await" => :deny,
      "unicorn/prefer-string-starts-ends-with" => :deny
    }
  ]

config :example,
  ecto_repos: [Example.Repo],
  generators: [timestamp_type: :utc_datetime]

config :example, Example.Repo,
  database: Path.expand("../example_dev.db", __DIR__),
  pool_size: 5

# Configure the endpoint
config :example, ExampleWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ExampleWeb.ErrorHTML, json: ExampleWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Example.PubSub,
  live_view: [signing_salt: "lF9FlYQi"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Record Ecto queries and log messages alongside LiveView events, and always
# keep sessions that hit an error.
config :phoenix_replay,
  collect: [{PhoenixReplay.Collector.Ecto, repo: Example.Repo}],
  logs: [level: :info],
  keep: [errors: true]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
