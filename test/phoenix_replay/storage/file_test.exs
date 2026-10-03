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

  describe "chunks" do
    alias PhoenixReplay.Recording.Event

    defp event(at), do: %Event{at: at, type: :info, data: %{tag: at}}

    test "appends chunks and reads them back ordered by sequence, with the latest metadata",
         %{opts: opts} do
      recording = %{Fixtures.counter_recording(id: "part") | events: []}

      assert FileStorage.fetch_partial("part", opts) == {:error, :not_found}
      assert :ok = FileStorage.append(recording, [{0, event(0)}, {2, event(2)}], opts)
      assert :ok = FileStorage.append(%{recording | url: "/later"}, [{1, event(1)}], opts)

      assert {:ok, %{url: "/later", events: events}} = FileStorage.fetch_partial("part", opts)
      assert Enum.map(events, & &1.at) == [0, 1, 2]
      assert FileStorage.partials(opts) == ["part"]
      assert FileStorage.list(opts) == []
    end

    test "saving the finished recording replaces its chunks", %{opts: opts} do
      recording = Fixtures.counter_recording(id: "done")
      :ok = FileStorage.append(recording, [{0, event(0)}], opts)

      assert :ok = FileStorage.save(recording, opts)
      assert FileStorage.partials(opts) == []
      assert FileStorage.fetch_partial("done", opts) == {:error, :not_found}
      assert File.ls!(opts[:path]) |> Enum.sort() == ["done.recording", "done.summary"]
    end

    test "deleting and clearing remove chunks too", %{opts: opts} do
      for id <- ~w(a b), do: FileStorage.append(Fixtures.counter_recording(id: id), [], opts)

      assert :ok = FileStorage.delete("a", opts)
      assert FileStorage.partials(opts) == ["b"]
      assert :ok = FileStorage.clear(opts)
      assert FileStorage.partials(opts) == []
    end

    test "recovers only part files this node wrote", %{opts: opts} do
      :ok = FileStorage.append(Fixtures.counter_recording(id: "mine"), [], opts)
      File.write!(Path.join(opts[:path], "theirs.othernode.part"), "")

      assert FileStorage.partials(opts) == ["mine"]
    end
  end
end
