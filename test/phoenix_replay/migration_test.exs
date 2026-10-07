defmodule PhoenixReplay.MigrationTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Migration
  alias PhoenixReplay.Test.Live.Counter
  alias PhoenixReplay.Test.ReplayMigrations.ClicksToCount

  test "finds the app's migrations, and applies those newer than a recording, in order" do
    assert {20_261_007_120_000, ClicksToCount} in Migration.all(Counter)
    assert Migration.latest(Counter) >= 20_261_007_120_000
    assert Migration.all(Kernel) == []

    migrations = [{1, ClicksToCount}, {2, ClicksToCount}]
    assert Migration.pending(migrations, nil) == migrations
    assert Migration.pending(migrations, 1) == [{2, ClicksToCount}]
    assert Migration.pending(migrations, 2) == []

    assert Migration.apply_to(migrations, Counter, %{clicks: 3}) == %{clicks: 3, count: 3}
    assert Migration.apply_to(migrations, Kernel, %{clicks: 3}) == %{clicks: 3}
  end
end
