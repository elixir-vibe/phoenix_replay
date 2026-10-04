# QuackDB needs Elixir 1.19, so it is a dependency only there; see mix.exs.
if Code.ensure_loaded?(QuackDB) do
  defmodule PhoenixReplay.Storage.Ecto.DuckDBTest do
    use ExUnit.Case, async: true
    # Tags apply only to tests defined after them.
    @moduletag :duckdb
    use PhoenixReplay.Test.EctoStorageCase, repo: PhoenixReplay.Test.DuckDBRepo
  end
end
