defmodule PhoenixReplay.Test.SQLiteRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :phoenix_replay, adapter: Ecto.Adapters.SQLite3
end

defmodule PhoenixReplay.Test.PostgresRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :phoenix_replay, adapter: Ecto.Adapters.Postgres
end

if Code.ensure_loaded?(QuackDB) do
  defmodule PhoenixReplay.Test.DuckDBRepo do
    @moduledoc false
    use Ecto.Repo, otp_app: :phoenix_replay, adapter: Ecto.Adapters.QuackDB
  end
end

defmodule PhoenixReplay.Test.Repos do
  @moduledoc false
  # Starts the repos the Ecto storage is tested on, recreates their
  # databases and migrates them with PhoenixReplay.Storage.Ecto.Migration,
  # as `mix ecto.reset` would. Tests check out sandboxed connections.

  # QuackDB is a dependency only on Elixir 1.19 and later; see mix.exs.
  @compile {:no_warn_undefined, [QuackDB.Server, Oban.Engines.QuackDB]}

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixReplay.Test.{DuckDBRepo, PostgresRepo, SQLiteRepo}

  @migrations [{1, PhoenixReplay.Storage.Ecto.Migration}, {2, PhoenixReplay.Test.ObanMigration}]

  @doc "Starts and migrates the repos available here, returning them."
  def start do
    started =
      [start_sqlite(), start_postgres(), start_duckdb()]
      |> Enum.reject(&is_nil/1)

    start_obans(started)
    for repo <- started, do: Sandbox.mode(repo, :manual)

    started
  end

  @doc """
  The Oban instance of `PhoenixReplay.Export.Queue.Oban`'s tests on
  `repo`. Started once, as an application starts its own, since in
  testing mode Oban checks its migrations with a connection outside the
  sandbox.
  """
  def oban(repo), do: Module.concat(repo, Oban)

  # Oban's `testing: :manual` on SQLite; oban_quackdb does not support it
  # yet, so DuckDB's instance runs no queues instead, to the same effect.
  defp start_obans(repos) do
    for repo <- repos, repo != PostgresRepo do
      {engine, testing} =
        if repo == SQLiteRepo,
          do: {Oban.Engines.Lite, [testing: :manual]},
          else: {Oban.Engines.QuackDB, []}

      {:ok, _pid} =
        Oban.start_link(
          [
            name: oban(repo),
            repo: repo,
            engine: engine,
            notifier: Oban.Notifiers.PG,
            peer: Oban.Peers.Isolated,
            prefix: false,
            queues: false,
            plugins: false
          ] ++ testing
        )
    end
  end

  defp start_sqlite, do: reset_and_start(SQLiteRepo)

  defp start_postgres do
    if PostgresRepo.config()[:database], do: reset_and_start(PostgresRepo)
  end

  # QuackDB serves DuckDB from its CLI, paired with the repo; install the
  # binary once with `MIX_ENV=test mix quackdb.install`.
  defp start_duckdb do
    if Code.ensure_loaded?(DuckDBRepo) do
      database = "tmp/test/replay.duckdb"
      File.mkdir_p!(Path.dirname(database))
      for file <- Path.wildcard(database <> "*"), do: File.rm!(file)

      {:ok, _supervisor} =
        Supervisor.start_link(
          QuackDB.Server.child_specs(
            server: [duckdb: :managed, database: database],
            client: {DuckDBRepo, pool_size: 2}
          ),
          strategy: :rest_for_one
        )

      Sandbox.mode(DuckDBRepo, :auto)
      migrate(DuckDBRepo)
      DuckDBRepo
    end
  end

  defp reset_and_start(repo) do
    adapter = repo.__adapter__()
    config = repo.config()
    _ = adapter.storage_down(config)
    :ok = adapter.storage_up(config)

    {:ok, _result, _apps} =
      Ecto.Migrator.with_repo(repo, &migrate/1, pool: DBConnection.ConnectionPool)

    {:ok, _pid} = repo.start_link()
    repo
  end

  defp migrate(repo), do: Ecto.Migrator.run(repo, @migrations, :up, all: true, log: false)
end
