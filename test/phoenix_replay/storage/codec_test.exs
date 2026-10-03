defmodule PhoenixReplay.Storage.CodecTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Summary
  alias PhoenixReplay.Storage.Codec
  alias PhoenixReplay.Test.Fixtures

  test "round-trips a recording" do
    recording = Fixtures.counter_recording()
    assert Codec.decode(Codec.encode(recording), Recording) == {:ok, recording}
  end

  test "rejects corrupt data, unknown atoms and other shapes" do
    assert Codec.decode("garbage", Recording) == {:error, :undecodable}

    unknown_atom = <<131, 119, 20, "phoenix_replay_nope_1">>
    assert Codec.decode(unknown_atom, Recording) == {:error, :undecodable}

    assert Codec.decode(Codec.encode(%{}), Recording) == {:error, :undecodable}

    assert Codec.decode(Codec.encode(Fixtures.counter_recording()), Summary) ==
             {:error, :undecodable}
  end
end
