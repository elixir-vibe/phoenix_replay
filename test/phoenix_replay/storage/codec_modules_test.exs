defmodule PhoenixReplay.Storage.CodecModulesTest do
  # Changes the code path and a node-wide flag, so runs alone.
  use ExUnit.Case, async: false

  alias PhoenixReplay.Storage.Codec

  @moduletag :tmp_dir

  test "decodes terms naming modules that exist but were never loaded", %{tmp_dir: tmp_dir} do
    # Compiled by another VM, so this one has never created the module's atom.
    name = "Elixir.PhoenixReplay.CodecProbe#{System.unique_integer([:positive])}"
    source = Path.join(tmp_dir, "probe.ex")
    File.write!(source, "defmodule #{String.replace_prefix(name, "Elixir.", "")} do\nend\n")
    {_output, 0} = System.cmd("elixirc", [source, "-o", tmp_dir], stderr_to_stdout: true)
    true = Code.prepend_path(tmp_dir)
    on_exit(fn -> Code.delete_path(tmp_dir) end)
    :persistent_term.erase({Codec, :modules_loaded})

    # [Name], encoded by hand: building the atom here would create it.
    binary = <<131, 108, 1::32, 119, byte_size(name), name::binary, 106>>

    assert {:ok, [module]} = Codec.decode(binary, :list)
    assert Atom.to_string(module) == name
  end

  test "still refuses atoms of no known module" do
    name = "phoenix_replay_never_an_atom_#{System.unique_integer([:positive])}"
    binary = <<131, 108, 1::32, 119, byte_size(name), name::binary, 106>>

    assert Codec.decode(binary, :list) == {:error, :undecodable}
  end
end
