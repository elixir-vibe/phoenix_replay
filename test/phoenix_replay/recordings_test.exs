defmodule PhoenixReplay.RecordingsTest do
  use ExUnit.Case, async: false

  alias PhoenixReplay.{Config, Recordings, Storage}
  alias PhoenixReplay.Recorder.Buffer
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
    listed = Enum.filter(Recordings.list(config), &(&1.id in ["buffered", "stored"]))
    assert [%{id: "buffered", live?: true}, %{id: "stored", live?: false}] = listed
  end

  test "fetches from the buffer first, then storage", %{config: config} do
    recording = Fixtures.counter_recording()
    assert Recordings.fetch(config, recording.id) == {:error, :not_found}

    Storage.save(config.storage, recording)
    assert Recordings.fetch(config, recording.id) == {:ok, recording}

    Buffer.open(recording, self(), config)
    on_exit(fn -> Buffer.close(recording.id) end)
    assert {:ok, %{events: []}} = Recordings.fetch(config, recording.id)
  end

  test "delete and clear notify subscribers", %{config: config} do
    Recordings.subscribe()
    Storage.save(config.storage, Fixtures.counter_recording(id: "a"))

    assert :ok = Recordings.delete(config, "a")
    assert_receive :recordings_changed
    assert :ok = Recordings.clear(config)
    assert_receive :recordings_changed
    assert Recordings.list(config) == []
  end
end
