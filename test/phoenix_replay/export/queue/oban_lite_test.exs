defmodule PhoenixReplay.Export.Queue.ObanLiteTest do
  # The Oban instance and the PubSub topic are shared with the other database's tests.
  use ExUnit.Case, async: false

  use PhoenixReplay.Test.ObanQueueCase,
    repo: PhoenixReplay.Test.SQLiteRepo,
    engine: Oban.Engines.Lite
end
