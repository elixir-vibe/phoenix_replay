defmodule PhoenixReplay.RecordingTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording

  test "generated ids are unique and valid" do
    ids = for _ <- 1..100, do: Recording.generate_id()
    assert Enum.uniq(ids) == ids
    assert Enum.all?(ids, &Recording.valid_id?/1)
  end

  test "valid_id?/1 rejects path segments and non-binaries" do
    refute Recording.valid_id?("../etc/passwd")
    refute Recording.valid_id?("a/b")
    refute Recording.valid_id?("")
    refute Recording.valid_id?(String.duplicate("a", 65))
    refute Recording.valid_id?(:id)
  end
end
