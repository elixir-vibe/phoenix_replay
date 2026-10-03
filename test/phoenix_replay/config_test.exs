defmodule PhoenixReplay.ConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Config

  test "defaults" do
    assert %Config{
             storage: {PhoenixReplay.Storage.File, []},
             sanitizer: PhoenixReplay.Sanitizer.Default,
             max_events: 10_000,
             retention: %{max_age: nil, max_count: nil, interval: 60_000},
             persist: %{attempts: 3, backoff: 1_000}
           } = Config.new([])
  end

  test "accepts a bare storage module" do
    assert Config.new(storage: MyStorage).storage == {MyStorage, []}
  end

  test "merges nested options over defaults" do
    config = Config.new(retention: [max_count: 5], persist: [attempts: 1])
    assert config.retention == %{max_age: nil, max_count: 5, interval: 60_000}
    assert config.persist == %{attempts: 1, backoff: 1_000}
  end

  test "rejects unknown keys and invalid values" do
    assert_raise ArgumentError, ~r/:max_events/, fn -> Config.new(max_events: 0) end
    assert_raise ArgumentError, ~r/:unknown/, fn -> Config.new(unknown: true) end
    assert_raise ArgumentError, ~r/:max_age/, fn -> Config.new(retention: [max_age: -1]) end
    assert_raise ArgumentError, ~r/:typo/, fn -> Config.new(persist: [typo: 1]) end
  end

  test "load/0 reads the application environment" do
    assert %Config{storage: {PhoenixReplay.Storage.File, [path: _]}, persist: %{attempts: 2}} =
             Config.load()
  end
end
