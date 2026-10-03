defmodule PhoenixReplay.Storage.FileTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias PhoenixReplay.Storage.File, as: FileStorage
  alias PhoenixReplay.Test.Fixtures

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir}, do: %{opts: [path: Path.join(tmp_dir, "recordings")]}

  test "saves, fetches and lists summaries newest first", %{opts: opts} do
    older = Fixtures.counter_recording(id: "older", connected_at: 1)
    newer = Fixtures.counter_recording(id: "newer", connected_at: 2)

    assert FileStorage.list(opts) == []
    assert :ok = FileStorage.save(older, opts)
    assert :ok = FileStorage.save(newer, opts)

    assert FileStorage.fetch("older", opts) == {:ok, older}
    assert [%{id: "newer", event_count: 6}, %{id: "older"}] = FileStorage.list(opts)
  end

  test "deletes one or all recordings", %{opts: opts} do
    for id <- ~w(a b), do: FileStorage.save(Fixtures.counter_recording(id: id), opts)

    assert :ok = FileStorage.delete("a", opts)
    assert :ok = FileStorage.delete("a", opts)
    assert FileStorage.fetch("a", opts) == {:error, :not_found}
    assert [%{id: "b"}] = FileStorage.list(opts)

    assert :ok = FileStorage.clear(opts)
    assert FileStorage.list(opts) == []
  end

  test "skips unreadable summaries instead of failing the listing", %{opts: opts} do
    FileStorage.save(Fixtures.counter_recording(id: "good"), opts)
    File.write!(Path.join(opts[:path], "bad.summary"), "garbage")

    log = capture_log(fn -> assert [%{id: "good"}] = FileStorage.list(opts) end)
    assert log =~ "bad.summary"
  end

  test "never touches paths outside the directory", %{opts: opts} do
    assert FileStorage.fetch("../escape", opts) == {:error, :not_found}
    assert FileStorage.delete("../escape", opts) == {:error, :not_found}
  end
end
