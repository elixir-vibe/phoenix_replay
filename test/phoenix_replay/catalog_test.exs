defmodule PhoenixReplay.CatalogTest do
  use ExUnit.Case, async: false

  alias PhoenixReplay.{Catalog, Config, Storage}
  alias PhoenixReplay.Recording.Filter
  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Test.Fixtures

  setup do
    config = Config.load()
    Storage.clear(config.storage)
    on_exit(fn -> Storage.clear(config.storage) end)
    %{config: config}
  end

  test "lists buffered recordings before stored ones, without duplicates", %{config: config} do
    stored = Fixtures.counter_recording(id: "stored", connected_at: 10)
    buffered = Fixtures.counter_recording(id: "buffered", connected_at: 1)
    Storage.save(config.storage, stored)
    Storage.save(config.storage, buffered)
    Buffer.open(buffered, self(), config)
    on_exit(fn -> Buffer.close("buffered") end)

    # Other tests' LiveViews may still be buffered; only this test's sessions matter.
    listed = Enum.filter(Catalog.list(config), &(&1.id in ["buffered", "stored"]))
    assert [%{id: "buffered", live?: true}, %{id: "stored", live?: false}] = listed
  end

  test "pages stored recordings in storage, or after checking each one", %{config: config} do
    for i <- 1..5 do
      Storage.save(config.storage, Fixtures.counter_recording(id: "r#{i}", connected_at: i))
    end

    filter = %Filter{}
    ids = fn {summaries, total} -> {Enum.map(summaries, & &1.id), total} end

    assert ids.(Catalog.query(config, filter, now: 10, offset: 1, limit: 2)) ==
             {~w(r4 r3), 5}

    allow = &(&1.id != "r4")

    assert ids.(Catalog.query(config, filter, now: 10, offset: 1, limit: 2, allow: allow)) ==
             {~w(r3 r2), 4}

    values = &Catalog.values(config, &1, filter, now: 10, limit: 10, allow: allow)
    assert values.(:view) == [{"PhoenixReplay.Test.Live.Counter", 4}]
    assert values.(:event) == [{"inc", 4}]

    assert Catalog.values(config, :view, filter, now: 10, limit: 10) == [
             {"PhoenixReplay.Test.Live.Counter", 5}
           ]
  end

  test "lists running sessions matching a filter", %{config: config} do
    recording = Fixtures.counter_recording(id: "running", connected_at: 1)
    Buffer.open(%{recording | client: %{recording.client | tab: "t9"}}, self(), config)
    on_exit(fn -> Buffer.close("running") end)

    assert [%{id: "running", live?: true}] =
             Catalog.live(%Filter{tab: "t9"}, System.system_time(:millisecond))

    assert Catalog.live(%Filter{tab: "other"}, 0) == []
  end

  test "fetches from the buffer first, then storage", %{config: config} do
    recording = Fixtures.counter_recording()
    assert Catalog.fetch(config, recording.id) == {:error, :not_found}

    Storage.save(config.storage, recording)
    assert Catalog.fetch(config, recording.id) == {:ok, recording}

    Buffer.open(recording, self(), config)
    on_exit(fn -> Buffer.close(recording.id) end)
    assert {:ok, %{events: []}} = Catalog.fetch(config, recording.id)
  end

  test "redacts buffered sessions with their own redactor", %{config: config} do
    recording = %{Fixtures.counter_recording() | url: "http://localhost/cards/4242"}
    session_config = %{config | redact: {PhoenixReplay.Redactor.Patterns, patterns: [~r/\d{4}$/]}}
    Buffer.open(recording, self(), session_config)
    on_exit(fn -> Buffer.close(recording.id) end)
    Buffer.put_url(recording.id, recording.url)

    assert Catalog.live?(recording.id)
    refute Catalog.live?("missing")

    assert %{url: "http://localhost/cards/[REDACTED]"} =
             Enum.find(Catalog.list(config), &(&1.id == recording.id))

    assert {:ok, %{url: "http://localhost/cards/[REDACTED]"}} =
             Catalog.fetch(config, recording.id)
  end

  test "delete and clear notify subscribers", %{config: config} do
    Catalog.subscribe()
    Storage.save(config.storage, Fixtures.counter_recording(id: "a"))

    assert :ok = Catalog.delete(config, "a")
    assert_receive :recordings_changed
    assert :ok = Catalog.clear(config)
    assert_receive :recordings_changed
    assert Catalog.list(config) == []
  end
end
