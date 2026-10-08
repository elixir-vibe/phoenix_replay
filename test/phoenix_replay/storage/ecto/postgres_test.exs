defmodule PhoenixReplay.Storage.Ecto.PostgresTest do
  # Runs when PHOENIX_REPLAY_POSTGRES_URL names a database to use, such as
  # postgres://postgres:postgres@localhost:5432/phoenix_replay_test.
  use ExUnit.Case, async: true
  # Tags apply only to tests defined after them.
  @moduletag :postgres
  use PhoenixReplay.Test.EctoStorageCase, repo: PhoenixReplay.Test.PostgresRepo
end
