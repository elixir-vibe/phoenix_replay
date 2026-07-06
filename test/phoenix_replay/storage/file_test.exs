defmodule PhoenixReplay.Storage.FileTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Storage.File, as: FileStorage

  defp tmp_dir(context) do
    dir = Path.join(System.tmp_dir!(), "phoenix_replay_file_test_#{context.test}")
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp sample_recording(id \\ "rec-1") do
    %Recording{
      id: id,
      view: PhoenixReplay.TestLive.Counter,
      url: "http://localhost/counter",
      params: %{},
      session: %{},
      connected_at: 1_700_000_000_000,
      events: [
        {0, :mount, %{assigns: %{count: 0}}},
        {500, :event, %{name: "inc"}},
        {600, :assigns, %{delta: %{count: 1}}}
      ]
    }
  end

  for format <- [:etf, :json] do
    describe "#{format} format" do
      @format format

      test "init creates directory", context do
        dir = tmp_dir(context)
        opts = [path: dir, format: @format]
        assert :ok = FileStorage.init(opts)
        assert File.dir?(dir)
      end

      test "save and get roundtrip", context do
        dir = tmp_dir(context)
        opts = [path: dir, format: @format]
        FileStorage.init(opts)

        rec = sample_recording()
        assert :ok = FileStorage.save(rec, opts)
        assert {:ok, loaded} = FileStorage.get("rec-1", opts)
        assert loaded.id == "rec-1"
        assert loaded.view == rec.view
        assert length(loaded.events) == 3
      end

      test "list returns recordings sorted by connected_at desc", context do
        dir = tmp_dir(context)
        opts = [path: dir, format: @format]
        FileStorage.init(opts)

        FileStorage.save(%{sample_recording("a") | connected_at: 1000}, opts)
        FileStorage.save(%{sample_recording("b") | connected_at: 3000}, opts)
        FileStorage.save(%{sample_recording("c") | connected_at: 2000}, opts)

        recs = FileStorage.list(opts)
        assert Enum.map(recs, & &1.id) == ["b", "c", "a"]
      end

      test "list_summaries returns lightweight recording metadata", context do
        dir = tmp_dir(context)
        opts = [path: dir, format: @format]
        FileStorage.init(opts)

        FileStorage.save(%{sample_recording("a") | connected_at: 1000}, opts)
        FileStorage.save(%{sample_recording("b") | connected_at: 3000}, opts)

        summaries = FileStorage.list_summaries(opts)

        assert Enum.map(summaries, & &1.id) == ["b", "a"]
        assert hd(summaries).event_count == 3
        refute Map.has_key?(hd(summaries), :events)
      end

      test "get returns :error for missing id", context do
        dir = tmp_dir(context)
        opts = [path: dir, format: @format]
        FileStorage.init(opts)

        assert :error = FileStorage.get("nonexistent", opts)
      end

      test "delete removes a recording", context do
        dir = tmp_dir(context)
        opts = [path: dir, format: @format]
        FileStorage.init(opts)

        FileStorage.save(sample_recording(), opts)
        assert :ok = FileStorage.delete("rec-1", opts)
        assert :error = FileStorage.get("rec-1", opts)
      end

      test "clear removes all recordings", context do
        dir = tmp_dir(context)
        opts = [path: dir, format: @format]
        FileStorage.init(opts)

        FileStorage.save(sample_recording("x"), opts)
        FileStorage.save(sample_recording("y"), opts)
        assert :ok = FileStorage.clear(opts)
        assert FileStorage.list(opts) == []
      end

      test "files use the serializer extension on disk", context do
        dir = tmp_dir(context)
        opts = [path: dir, format: @format]
        FileStorage.init(opts)
        FileStorage.save(sample_recording(), opts)

        [file] = File.ls!(dir)
        assert String.ends_with?(file, PhoenixReplay.Storage.Serializer.extension(@format))
      end
    end
  end
end
