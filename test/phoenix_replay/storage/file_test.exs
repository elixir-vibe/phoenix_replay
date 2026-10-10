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

  test "keeps read summaries indexed and follows files other nodes write", %{
    opts: opts,
    tmp_dir: tmp_dir
  } do
    dir = opts[:path]
    FileStorage.save(Fixtures.counter_recording(id: "mine", connected_at: 2), opts)
    assert [%{id: "mine"}] = FileStorage.list(opts)

    # An indexed summary is not read again.
    File.write!(Path.join(dir, "mine.summary"), "unreadable")
    assert [%{id: "mine"}] = FileStorage.list(opts)

    # Another node saves into the same directory.
    elsewhere = [path: Path.join(tmp_dir, "elsewhere")]
    FileStorage.save(Fixtures.counter_recording(id: "theirs", connected_at: 1), elsewhere)

    for ext <- ~w(.recording .summary),
        do:
          File.cp!(Path.join(elsewhere[:path], "theirs" <> ext), Path.join(dir, "theirs" <> ext))

    assert [%{id: "mine"}, %{id: "theirs"}] = FileStorage.list(opts)

    # And deletes one.
    File.rm!(Path.join(dir, "mine.summary"))
    assert [%{id: "theirs"}] = FileStorage.list(opts)
  end

  test "pages summaries matching a filter through the storage facade", %{opts: opts} do
    storage = {FileStorage, opts}

    for i <- 1..5,
        do: FileStorage.save(Fixtures.counter_recording(id: "r#{i}", connected_at: i), opts)

    filter = %PhoenixReplay.Recording.Filter{}

    assert {[%{id: "r4"}, %{id: "r3"}], 5} =
             PhoenixReplay.Storage.query(storage, filter, now: 10, offset: 1, limit: 2)

    Process.sleep(2)
    saved = System.system_time(:millisecond)
    Process.sleep(2)
    FileStorage.save(Fixtures.counter_recording(id: "late", connected_at: 0), opts)

    assert {[%{id: "late"}], 1} =
             PhoenixReplay.Storage.query(storage, filter, now: 10, since: saved, limit: 5)

    assert {_page, 5} =
             PhoenixReplay.Storage.query(storage, filter, now: 10, until: saved, limit: 0)
  end

  test "orders sessions that started together by id", %{opts: opts} do
    for id <- ~w(t1 t2 t3),
        do: FileStorage.save(Fixtures.counter_recording(id: id, connected_at: 7), opts)

    assert ~w(t3 t2 t1) == Enum.map(FileStorage.list(opts), & &1.id)
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

    # Two VMs that are not distributed share a node name on one host.
    test "leaves the parts of another VM of this node while it runs", %{opts: opts} do
      :ok = FileStorage.append(Fixtures.counter_recording(id: "mine"), [], opts)
      [own] = File.ls!(opts[:path])
      node = own |> String.split(".") |> Enum.at(1) |> String.split("-") |> hd()

      # Another VM, still running.
      port = Port.open({:spawn_executable, System.find_executable("sleep")}, args: ["30"])
      {:os_pid, running} = Port.info(port, :os_pid)
      on_exit(fn -> if Port.info(port), do: Port.close(port) end)
      File.write!(Path.join(opts[:path], "live.#{node}-#{running}.part"), "")

      # One that is gone, as after a crash.
      {gone, 0} = System.cmd("sh", ["-c", "echo $$"])
      File.write!(Path.join(opts[:path], "crashed.#{node}-#{String.trim(gone)}.part"), "")

      # Written before the tag had a process id.
      File.write!(Path.join(opts[:path], "older.#{node}.part"), "")

      assert Enum.sort(FileStorage.partials(opts)) == ["crashed", "mine", "older"]
    end
  end

  describe "by visit" do
    alias PhoenixReplay.Recording.{Event, Filter}
    alias PhoenixReplay.Storage

    # The same visits as the Ecto backends' tests, paged in memory by
    # PhoenixReplay.Recording.Filter.
    setup %{opts: opts} do
      error = %Event{at: 9, type: :log, data: %{level: :error, message: "x", metadata: %{}}}

      for {id, at, visit, extra} <- [
            {"v1a", 1, "v1", []},
            {"v1b", 5, "v1", [error: error]},
            {"v2", 3, "v2", [view: Other]},
            {"solo", 4, nil, []}
          ] do
        recording = Fixtures.counter_recording(id: id, connected_at: at)

        :ok =
          FileStorage.save(
            %{
              recording
              | view: extra[:view] || recording.view,
                events: recording.events ++ List.wrap(extra[:error]),
                client: %{recording.client | visit: visit}
            },
            opts
          )
      end

      %{storage: {FileStorage, opts}}
    end

    defp visit_ids({summaries, total}), do: {Enum.map(summaries, & &1.id), total}

    test "pages visits by when they started, with every recording of each", %{storage: storage} do
      query =
        &visit_ids(Storage.query(storage, Filter.from_params(&1), [now: 10, by: :visit] ++ &2))

      assert query.(%{}, limit: 10) == {~w(solo v2 v1a v1b), 3}
      assert query.(%{}, offset: 1, limit: 1) == {~w(v2), 3}
      assert query.(%{"errors" => "1"}, limit: 10) == {~w(v1a v1b), 1}
      assert query.(%{"view" => "Other"}, limit: 10) == {~w(v2), 1}
      assert query.(%{"visit" => "v1"}, limit: 10) == {~w(v1a v1b), 1}
      assert query.(%{"visit" => "solo"}, limit: 10) == {~w(solo), 1}
    end

    test "counts each visit once in values and the chart", %{storage: storage} do
      values = &Storage.values(storage, :view, %Filter{}, [now: 10, limit: 10] ++ &1)

      assert values.(by: :visit) == [{"PhoenixReplay.Test.Live.Counter", 2}, {"Other", 1}]
      assert values.([]) == [{"PhoenixReplay.Test.Live.Counter", 3}, {"Other", 1}]

      assert Storage.histogram(storage, %Filter{}, 2, now: 10, by: :visit) ==
               [{0, 1, 1}, {2, 1, 0}, {4, 1, 0}]
    end
  end
end
