defmodule PhoenixReplay.Storage.Ecto.PostgresTest do
  # Runs when PHOENIX_REPLAY_POSTGRES_URL names a database to use, such as
  # postgres://postgres:postgres@localhost:5432/phoenix_replay_test. Its
  # recordings table is recreated.
  use ExUnit.Case, async: false
  # Tags apply only to tests defined after them.
  @moduletag :postgres
  use PhoenixReplay.Test.EctoStorageCase

  defmodule Repo do
    use Ecto.Repo, otp_app: :phoenix_replay, adapter: Ecto.Adapters.Postgres
  end

  @migrations [{1, PhoenixReplay.Test.EctoMigration}]

  # ExUnit runs setup_all even when test_helper excludes every test here.
  setup_all do
    case System.get_env("PHOENIX_REPLAY_POSTGRES_URL") do
      nil -> :ok
      url -> start(url)
    end
  end

  defp start(url) do
    _ = Repo.__adapter__().storage_up(Ecto.Repo.Supervisor.parse_url(url))
    start_supervised!({Repo, url: url, pool_size: 2, log: false})

    Ecto.Migrator.run(Repo, @migrations, :down, all: true, log: false)
    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)
    %{opts: [repo: Repo]}
  end
end
