defmodule PhoenixReplay.Storage.Ecto.SQLiteTest do
  use ExUnit.Case, async: false
  use PhoenixReplay.Test.EctoStorageCase

  defmodule Repo do
    use Ecto.Repo, otp_app: :phoenix_replay, adapter: Ecto.Adapters.SQLite3
  end

  setup_all do
    database =
      Path.join(System.tmp_dir!(), "phoenix_replay_#{System.unique_integer([:positive])}.db")

    on_exit(fn -> for file <- Path.wildcard(database <> "*"), do: File.rm(file) end)

    start_supervised!({Repo, database: database, pool_size: 1, log: false})
    Ecto.Migrator.up(Repo, 1, PhoenixReplay.Test.EctoMigration, log: false)
    %{opts: [repo: Repo]}
  end
end
