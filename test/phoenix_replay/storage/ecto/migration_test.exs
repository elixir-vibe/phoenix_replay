defmodule PhoenixReplay.Storage.Ecto.MigrationTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Storage.Ecto.Migration

  defmodule Repo do
    use Ecto.Repo, otp_app: :phoenix_replay, adapter: Ecto.Adapters.SQLite3
  end

  # The table as PhoenixReplay 0.4 created it.
  defmodule Released do
    use Ecto.Migration
    def up, do: Migration.up(version: 1)
    def down, do: Migration.down(version: 1)
  end

  defmodule Upgrade do
    use Ecto.Migration
    def up, do: Migration.up(from: 1)
    def down, do: Migration.down(from: 1)
  end

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    database = Path.join(tmp_dir, "migration.sqlite3")
    start_supervised!({Repo, database: database, pool_size: 1, log: false})
    :ok
  end

  defp columns do
    %{columns: names} = Repo.query!("SELECT * FROM phoenix_replay_recordings LIMIT 0")
    MapSet.new(names)
  end

  test "upgrades the released table and back" do
    run = &Ecto.Migrator.run(Repo, &1, &2, all: true, log: false)
    new = MapSet.new(~w(error_count tab viewport device source))

    run.([{1, Released}], :up)
    assert MapSet.disjoint?(columns(), new)

    run.([{1, Released}, {2, Upgrade}], :up)
    assert MapSet.subset?(new, columns())

    run.([{1, Released}, {2, Upgrade}], :down)

    assert_raise Exqlite.Error, ~r/no such table/, &columns/0
  end
end
