# QuackDB needs Elixir 1.19, so it is a dependency only there; see mix.exs.
if Code.ensure_loaded?(Oban.Engines.QuackDB) do
  defmodule PhoenixReplay.Export.Queue.ObanQuackDBTest do
    use ExUnit.Case, async: false
    # Tags apply only to tests defined after them.
    @moduletag :duckdb

    use PhoenixReplay.Test.ObanQueueCase,
      repo: PhoenixReplay.Test.DuckDBRepo,
      engine: Oban.Engines.QuackDB,
      sandbox: false
  end
end
