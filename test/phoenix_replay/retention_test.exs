defmodule PhoenixReplay.RetentionTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.{Config, Retention, Storage}
  alias PhoenixReplay.Recording.Summary
  alias PhoenixReplay.Test.Fixtures

  @moduletag :tmp_dir

  defp summary(id, connected_at), do: %Summary{id: id, view: "V", connected_at: connected_at}

  test "expired/3 selects by age and by count" do
    summaries = [summary("c", 300), summary("b", 200), summary("a", 100)]

    assert Retention.expired(summaries, %{max_age: nil, max_count: nil}, 1000) == []
    assert [%{id: "a"}] = Retention.expired(summaries, %{max_age: 850, max_count: nil}, 1000)

    assert [%{id: "b"}, %{id: "a"}] =
             Retention.expired(summaries, %{max_age: nil, max_count: 1}, 1000)

    assert [%{id: "b"}, %{id: "a"}] =
             Retention.expired(summaries, %{max_age: 850, max_count: 1}, 1000)
  end

  test "prune/2 deletes expired recordings", %{tmp_dir: tmp_dir} do
    config =
      Config.new(storage: {PhoenixReplay.Storage.File, path: tmp_dir}, retention: [max_count: 1])

    for {id, at} <- [{"old", 1}, {"new", 2}],
        do: Storage.save(config.storage, Fixtures.counter_recording(id: id, connected_at: at))

    assert Retention.prune(config) == ["old"]
    assert [%{id: "new"}] = Storage.list(config.storage)
  end
end
