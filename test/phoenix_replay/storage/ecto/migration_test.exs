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
    def up, do: Migration.up(from: 1, version: 2)
    def down, do: Migration.down(from: 1, version: 2)
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

  test "keeps rows stored under the released table readable after upgrading" do
    run = &Ecto.Migrator.run(Repo, &1, &2, all: true, log: false)
    run.([{1, Released}], :up)

    recording = PhoenixReplay.Test.Fixtures.counter_recording(id: "old", connected_at: 5)
    summary = PhoenixReplay.Recording.Summary.new(recording)

    Repo.insert_all("phoenix_replay_recordings", [
      %{
        id: "old",
        view: summary.view,
        url: summary.url,
        connected_at: 5,
        event_count: summary.event_count,
        duration_ms: summary.duration_ms,
        event_names: PhoenixReplay.Storage.Codec.encode(summary.event_names),
        data: PhoenixReplay.Storage.Codec.encode(recording)
      }
    ])

    run.([{1, Released}, {2, Upgrade}], :up)

    assert [%{id: "old", error_count: 0, saved_at: nil, viewport: nil, device: nil}] =
             PhoenixReplay.Storage.Ecto.list(repo: Repo)

    assert {:ok, ^recording} = PhoenixReplay.Storage.Ecto.fetch("old", repo: Repo)
  end

  test "reports a database error as a failed save instead of raising" do
    # No table: every insert fails.
    assert {:error, %Exqlite.Error{}} =
             PhoenixReplay.Storage.Ecto.save(PhoenixReplay.Test.Fixtures.counter_recording(),
               repo: Repo
             )
  end

  test "upgrades the released table and back" do
    run = &Ecto.Migrator.run(Repo, &1, &2, all: true, log: false)
    new = MapSet.new(~w(error_count tab viewport device source saved_at))

    run.([{1, Released}], :up)
    assert MapSet.disjoint?(columns(), new)

    run.([{1, Released}, {2, Upgrade}], :up)
    assert MapSet.subset?(new, columns())

    run.([{1, Released}, {2, Upgrade}], :down)

    assert_raise Exqlite.Error, ~r/no such table/, &columns/0
  end
end
