defmodule PhoenixReplay.ConfigTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Config

  test "defaults" do
    assert %Config{
             storage: {PhoenixReplay.Storage.File, []},
             sanitizer: PhoenixReplay.Sanitizer.Default,
             max_events: 10_000,
             sample_rate: 1.0,
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

  test "normalizes the sample rate and applies overrides" do
    assert Config.new(sample_rate: 0).sample_rate == 0.0
    assert Config.load(sample_rate: 0.25, max_events: 5).sample_rate == 0.25
    assert Config.load(max_events: 5).max_events == 5
    assert_raise ArgumentError, ~r/:sample_rate/, fn -> Config.new(sample_rate: 1.5) end
  end

  test "normalizes collectors" do
    assert Config.new([]).collect == []

    assert Config.new(
             collect: [
               MyCollector,
               {MyCollector, limit: 5},
               [:my_app, :checkout, :stop],
               {[:my_app, :search, :stop], metadata: [:query]}
             ]
           ).collect == [
             {MyCollector, []},
             {MyCollector, limit: 5},
             {PhoenixReplay.Collector.Generic, event: [:my_app, :checkout, :stop]},
             {PhoenixReplay.Collector.Generic,
              event: [:my_app, :search, :stop], metadata: [:query]}
           ]

    assert_raise ArgumentError, ~r/configuration :collect: "nope"/, fn ->
      Config.new(collect: ["nope"])
    end
  end

  test "validates tail sampling, logs, redaction and memory" do
    assert Config.new([]).keep == %{rate: 1.0, errors: false, marks: false, slower_than: nil}

    assert Config.new(keep: [rate: 0, errors: true, marks: true]).keep == %{
             rate: 0.0,
             errors: true,
             marks: true,
             slower_than: nil
           }

    assert_raise ArgumentError, ~r/:rate/, fn -> Config.new(keep: [rate: 2]) end

    assert Config.new([]).logs == nil
    assert Config.new(logs: []).logs == %{level: :info, metadata: [], limit: 1_000}
    assert_raise ArgumentError, ~r/:level/, fn -> Config.new(logs: [level: :loud]) end

    assert Config.new([]).redact == nil
    assert Config.new(redact: []).redact == nil

    assert {PhoenixReplay.Redactor.Patterns,
            patterns: [%Regex{source: "a+"}, %Regex{source: "b"}]} =
             Config.new(redact: ["a+", ~r/b/]).redact

    assert Config.new(redact: {MyRedactor, x: 1}).redact == {MyRedactor, x: 1}
    assert Config.new(redact: MyRedactor).redact == {MyRedactor, []}

    assert_raise ArgumentError, ~r/configuration :redact: :email/, fn ->
      Config.new(redact: [:email])
    end

    assert Config.new([]).flush == %{events: 200, interval: 5_000}
    assert Config.new(flush: [events: 50]).flush == %{events: 50, interval: 5_000}
    assert Config.new(flush: false).flush == nil
    assert_raise ArgumentError, ~r/:interval/, fn -> Config.new(flush: [interval: 0]) end

    assert Config.new(max_memory: 1_024).max_memory == 1_024
    assert_raise ArgumentError, ~r/:max_memory/, fn -> Config.new(max_memory: 0) end
  end

  test "normalizes request context" do
    assert Config.new([]).context == %{headers: [], landing: nil}

    context =
      Config.new(
        context: [
          headers: ["Accept-Language", :cf_ipcountry],
          landing: [params: [:utm, "ref", :click_ids, "ref"], attribution: :last]
        ]
      ).context

    assert context.headers == ["accept-language", "cf_ipcountry"]

    assert context.landing == %{
             params:
               ~w(utm_source utm_medium utm_campaign utm_term utm_content ref gclid fbclid msclkid),
             referrer: true,
             attribution: :last
           }

    assert_raise ArgumentError, ~r/"cookie"/, fn -> Config.new(context: [headers: ["Cookie"]]) end

    assert_raise ArgumentError, ~r/:params/, fn ->
      Config.new(context: [landing: [params: [:nope]]])
    end

    assert_raise ArgumentError, ~r/:attribution/, fn ->
      Config.new(context: [landing: [attribution: :middle]])
    end
  end

  test "records form controls with client state unless told not to" do
    assert %{inputs: true, debounce: 300} = Config.new([]).state
    assert %{inputs: false, flush: 1_000} = Config.new(state: [inputs: false]).state
    assert_raise ArgumentError, ~r/:inputs/, fn -> Config.new(state: [inputs: :yes]) end
    assert_raise ArgumentError, ~r/:debounce/, fn -> Config.new(state: [debounce: 0]) end
  end

  test "exports videos only once configured, with an endpoint" do
    assert Config.new([]).export == nil

    assert %{endpoint: MyAppWeb.Endpoint, fps: 30, idle: 3_000, max_concurrency: 1, hold: 1_000} =
             Config.new(export: [endpoint: MyAppWeb.Endpoint]).export

    assert Config.new(export: [endpoint: MyAppWeb.Endpoint, idle: nil]).export.idle == nil
    assert Config.new(export: false).export == nil
    assert_raise ArgumentError, ~r/:fps/, fn -> Config.new(export: [fps: 0]) end

    assert_raise ArgumentError, ~r/:frame_layout/, fn ->
      Config.new(export: [frame_layout: "x"])
    end
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

  test "merges overrides of every nested option onto what is set" do
    assert Config.new(flush: [events: 50], flush: [interval: 9]).flush == %{
             events: 50,
             interval: 9
           }

    assert Config.new(pointer: [sample: 30], pointer: [flush: 500]).pointer.sample == 30
    assert Config.new(logs: [level: :warning], logs: [limit: 5]).logs.level == :warning
    assert Config.new(flush: false, flush: [events: 10]).flush == %{events: 10, interval: 5_000}
  end

  test "switches options off with nil or false, and on with true" do
    for key <- [:flush, :logs, :pointer, :redact, :max_memory], off <- [nil, false] do
      assert Map.fetch!(Config.new([{key, off}]), key) == nil
    end

    assert Config.new(redact: []).redact == nil
    assert Config.new(context: [landing: false]).context.landing == nil
    assert Config.new(logs: true).logs == %{level: :info, metadata: [], limit: 1_000}
    assert Config.new(flush: [events: 10], flush: true).flush.events == 10

    assert_raise ArgumentError, ~r/:flush: "x"/, fn -> Config.new(flush: "x") end
  end
end
