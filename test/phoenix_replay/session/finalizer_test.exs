defmodule PhoenixReplay.Session.FinalizerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias PhoenixReplay.Config
  alias PhoenixReplay.Session.Finalizer
  alias PhoenixReplay.Test.Fixtures

  @moduletag :tmp_dir

  test "saves through the configured storage", %{tmp_dir: tmp_dir} do
    recording = Fixtures.counter_recording()
    config = Config.new(storage: {PhoenixReplay.Storage.File, path: tmp_dir})

    assert Finalizer.persist(recording, config) == {:ok, recording}
    assert PhoenixReplay.Storage.fetch(config.storage, recording.id) == {:ok, recording}
  end

  defmodule FailingRedactor do
    @moduledoc false
    @behaviour PhoenixReplay.Redactor

    @impl true
    def redact(_text, _opts), do: {:error, :model_unavailable}
  end

  test "redacts before saving", %{tmp_dir: tmp_dir} do
    recording = %{Fixtures.counter_recording() | url: "http://localhost/cards/4242"}

    config =
      Config.new(storage: {PhoenixReplay.Storage.File, path: tmp_dir}, redact: [~r/\d{4}$/])

    assert {:ok, _recording} = Finalizer.persist(recording, config)

    assert {:ok, %{url: "http://localhost/cards/[REDACTED]"}} =
             PhoenixReplay.Storage.fetch(config.storage, recording.id)
  end

  test "saves nothing when redaction fails" do
    recording = Fixtures.counter_recording()

    config =
      Config.new(
        storage: {PhoenixReplay.Test.FailingStorage, notify: self()},
        redact: {FailingRedactor, []}
      )

    log =
      capture_log(fn ->
        assert Finalizer.persist(recording, config) == {:error, :redaction_failed}
      end)

    refute_received {:save_attempt, _id}
    assert log =~ "redaction_failed"
  end

  test "retries, then gives up with the last error" do
    recording = Fixtures.counter_recording()

    config =
      Config.new(
        storage: {PhoenixReplay.Test.FailingStorage, notify: self()},
        persist: [attempts: 3, backoff: 0]
      )

    log =
      capture_log(fn -> assert Finalizer.persist(recording, config) == {:error, :unavailable} end)

    for _ <- 1..3, do: assert_received({:save_attempt, _id})
    refute_received {:save_attempt, _id}
    assert log =~ "dropping recording #{recording.id}"
  end
end
