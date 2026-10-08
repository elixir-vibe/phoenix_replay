defmodule PhoenixReplay.Storage.Ecto.SQLiteTest do
  use ExUnit.Case, async: true
  use PhoenixReplay.Test.EctoStorageCase, repo: PhoenixReplay.Test.SQLiteRepo
end
