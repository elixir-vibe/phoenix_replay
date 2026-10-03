import Config

config :volt,
  root: ".",
  entry: "priv/ts/dashboard.ts",
  outdir: "priv/static",
  output_layout: :flat,
  hash: false,
  code_splitting: false,
  sourcemap: false,
  # The layouts load the host application's own Phoenix and LiveView clients,
  # so the client always matches the server. See PhoenixReplay.Web.Assets.
  external: %{"phoenix" => "Phoenix", "phoenix_live_view" => "LiveView"},
  resolve_dirs: ["deps"],
  sources: ["priv/ts/**/*.ts"],
  ignore: ["_build/**", "deps/**", "doc/**", "node_modules/**", "example/**"],
  tailwind: [
    css: "priv/css/dashboard.css",
    sources: [%{base: "lib/phoenix_replay/web/", pattern: "**/*.ex"}]
  ]

config :volt, :lint,
  plugins: ["typescript"],
  env: ["browser"],
  rules: %{
    "correctness" => :deny,
    "typescript/no-floating-promises" => :deny,
    "typescript/no-explicit-any" => :deny
  },
  tsgolint: "node_modules/.bin/tsgolint"

if config_env() == :test do
  import_config "test.exs"
end
