defmodule PhoenixReplay.Test.ObanMigration do
  @moduledoc """
  Creates Oban's jobs table in the test repos, for
  `PhoenixReplay.Export.Queue.Oban`: with oban_quackdb's migration on
  DuckDB, and Oban's own on the others.
  """

  use Ecto.Migration

  @compile {:no_warn_undefined, Oban.Migrations.QuackDB}

  def up do
    if quackdb?(), do: Oban.Migrations.QuackDB.up(), else: Oban.Migration.up()
  end

  def down do
    if quackdb?(), do: Oban.Migrations.QuackDB.down(), else: Oban.Migration.down()
  end

  defp quackdb?, do: repo().__adapter__() == Ecto.Adapters.QuackDB
end
