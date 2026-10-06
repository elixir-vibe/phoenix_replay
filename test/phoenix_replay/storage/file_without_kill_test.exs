defmodule PhoenixReplay.Storage.FileWithoutKillTest do
  # It empties PATH, which every test in the VM shares, so it runs alone.
  use ExUnit.Case, async: false

  alias PhoenixReplay.Storage.File, as: FileStorage
  alias PhoenixReplay.Test.Fixtures

  @moduletag :tmp_dir

  test "leaves a part whose writer it cannot ask about, without kill", %{tmp_dir: tmp_dir} do
    opts = [path: Path.join(tmp_dir, "recordings")]
    :ok = FileStorage.append(Fixtures.counter_recording(id: "mine"), [], opts)
    [own] = File.ls!(opts[:path])
    node = own |> String.split(".") |> Enum.at(1) |> String.split("-") |> hd()

    # A VM that is gone, as after a crash.
    {gone, 0} = System.cmd("sh", ["-c", "echo $$"])
    File.write!(Path.join(opts[:path], "crashed.#{node}-#{String.trim(gone)}.part"), "")
    File.write!(Path.join(opts[:path], "crashed-too.#{node}-#{String.trim(gone)}.part"), "")
    assert Enum.sort(FileStorage.partials(opts)) == ["crashed", "crashed-too", "mine"]

    path = System.get_env("PATH")
    System.put_env("PATH", "")

    try do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert FileStorage.partials(opts) == ["mine"]
          assert FileStorage.partials(opts) == ["mine"]
        end)

      # Warned at most once per boot, however many parts are left.
      assert length(String.split(log, "no kill")) <= 2
    after
      System.put_env("PATH", path)
    end
  end
end
