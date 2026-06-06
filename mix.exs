defmodule PhoenixReplay.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/elixir-vibe/phoenix_replay"

  def project do
    [
      app: :phoenix_replay,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "PhoenixReplay",
      description: "Session recording and replay for Phoenix LiveView",
      dialyzer: [plt_add_apps: [:mix]],
      aliases: aliases()
    ]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PhoenixReplay.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:ecto, "~> 3.13", optional: true},
      {:ecto_sql, "~> 3.13", only: :test},
      {:ecto_sqlite3, "~> 0.22", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.2.0", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv/static mix.exs README.md CHANGELOG.md LICENSE screenshot.jpg)
    ]
  end

  defp docs do
    [
      main: "PhoenixReplay",
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp aliases do
    [
      ci: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test",
        "credo --strict",
        "ex_dna",
        "reach.check --smells --strict",
        "dialyzer",
        "deps.unlock --check-unused"
      ]
    ]
  end
end
