# QuackDB needs Elixir 1.19, so it is a dependency only there; see mix.exs.
if Code.ensure_loaded?(QuackDB) do
  defmodule PhoenixReplay.Storage.Ecto.DuckDBTest do
    # DuckDB through QuackDB, which runs DuckDB's CLI as a server; install it
    # once with `MIX_ENV=test mix quackdb.install`.
    use ExUnit.Case, async: false
    # Tags apply only to tests defined after them.
    @moduletag :duckdb
    use PhoenixReplay.Test.EctoStorageCase

    defmodule Repo do
      use Ecto.Repo, otp_app: :phoenix_replay, adapter: Ecto.Adapters.QuackDB
    end

    setup_all do
      dir =
        Path.join(
          System.tmp_dir!(),
          "phoenix_replay_duckdb_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)

      for child <-
            QuackDB.Server.child_specs(
              server: [duckdb: :managed, database: Path.join(dir, "replay.duckdb")],
              client: {Repo, pool_size: 2, log: false}
            ),
          do: start_supervised!(child)

      Ecto.Migrator.up(Repo, 1, PhoenixReplay.Test.EctoMigration, log: false)
      %{opts: [repo: Repo]}
    end
  end
end
