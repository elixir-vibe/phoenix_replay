defmodule PhoenixReplay.Recorder.PersisterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias PhoenixReplay.Config
  alias PhoenixReplay.Recorder.Persister
  alias PhoenixReplay.Test.Fixtures

  @moduletag :tmp_dir

  test "saves through the configured storage", %{tmp_dir: tmp_dir} do
    recording = Fixtures.counter_recording()
    config = Config.new(storage: {PhoenixReplay.Storage.File, path: tmp_dir})

    assert Persister.persist(recording, config) == :ok
    assert PhoenixReplay.Storage.fetch(config.storage, recording.id) == {:ok, recording}
  end

  test "retries, then gives up with the last error" do
    recording = Fixtures.counter_recording()

    config =
      Config.new(
        storage: {PhoenixReplay.Test.FailingStorage, notify: self()},
        persist: [attempts: 3, backoff: 0]
      )

    log =
      capture_log(fn -> assert Persister.persist(recording, config) == {:error, :unavailable} end)

    for _ <- 1..3, do: assert_received({:save_attempt, _id})
    refute_received {:save_attempt, _id}
    assert log =~ "dropping recording #{recording.id}"
  end
end
