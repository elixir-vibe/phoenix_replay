defmodule PhoenixReplay.Storage.FileRootTest do
  # Changes the working directory of the whole VM, so runs alone.
  use ExUnit.Case, async: false

  alias PhoenixReplay.Storage.File, as: FileStorage
  alias PhoenixReplay.Test.Fixtures

  @moduletag :tmp_dir

  test "resolves relative paths against the directory PhoenixReplay started in", %{
    tmp_dir: tmp_dir
  } do
    elsewhere = Path.join(tmp_dir, "elsewhere")
    File.mkdir_p!(elsewhere)
    opts = [path: "tmp/root_test_recordings"]
    on_exit(fn -> File.rm_rf!(Path.join(File.cwd!(), "tmp/root_test_recordings")) end)

    # As Phoenix's code reloader does while it compiles a path dependency.
    File.cd!(elsewhere, fn ->
      :ok = FileStorage.append(Fixtures.counter_recording(id: "rooted"), [], opts)
    end)

    refute File.exists?(Path.join(elsewhere, "tmp/root_test_recordings"))
    assert FileStorage.partials(opts) == ["rooted"]
  end
end
