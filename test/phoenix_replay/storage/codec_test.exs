defmodule PhoenixReplay.Storage.CodecTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Client
  alias PhoenixReplay.Recording.Client.Landing
  alias PhoenixReplay.Recording.Summary
  alias PhoenixReplay.Storage.Codec
  alias PhoenixReplay.Test.Fixtures

  test "round-trips a recording" do
    recording = Fixtures.counter_recording()
    assert Codec.decode(Codec.encode(recording), Recording) == {:ok, recording}
  end

  test "fills fields added after the data was written" do
    written_by_older_version =
      %Summary{id: "a", view: "V", connected_at: 0}
      |> Map.from_struct()
      |> Map.delete(:event_names)
      |> Map.put(:__struct__, Summary)

    assert {:ok, %Summary{id: "a", event_names: []}} =
             written_by_older_version |> Codec.encode() |> Codec.decode(Summary)
  end

  test "brings the client context of a recording from before 0.6 up to date" do
    recording = Fixtures.counter_recording()

    stored_by_0_5 = %{
      recording
      | client: %{
          viewport: nil,
          user_agent: "Agent",
          tab: "t1",
          referer: "http://x/form",
          headers: %{},
          landing: %{path: "/", at: 1, params: %{}, referrer: nil}
        }
    }

    assert {:ok, %Recording{client: client}} =
             stored_by_0_5 |> Codec.encode() |> Codec.decode(Recording)

    assert client == %Client{
             user_agent: "Agent",
             tab: "t1",
             navigated_from: "http://x/form",
             landing: %Landing{path: "/", at: 1}
           }
  end

  test "decodes lists" do
    assert Codec.decode(Codec.encode(["a"]), :list) == {:ok, ["a"]}
    assert Codec.decode(Codec.encode(%{}), :list) == {:error, :undecodable}
  end

  test "rejects corrupt data, unknown atoms and other shapes" do
    assert Codec.decode("garbage", Recording) == {:error, :undecodable}

    unknown_atom = <<131, 119, 20, "phoenix_replay_nope_1">>
    assert Codec.decode(unknown_atom, Recording) == {:error, :undecodable}

    assert Codec.decode(Codec.encode(%{}), Recording) == {:error, :undecodable}

    assert Codec.decode(Codec.encode(Fixtures.counter_recording()), Summary) ==
             {:error, :undecodable}
  end

  test "frames survive appending and stop at a torn or corrupt frame" do
    binary =
      IO.iodata_to_binary([Codec.frame(:first), Codec.frame(%{second: [2]}), Codec.frame(3)])

    assert Codec.decode_frames(binary) == [:first, %{second: [2]}, 3]

    torn = binary_part(binary, 0, byte_size(binary) - 2)
    assert Codec.decode_frames(torn) == [:first, %{second: [2]}]

    second_payload_byte = byte_size(IO.iodata_to_binary(Codec.frame(:first))) + 12
    <<head::binary-size(^second_payload_byte), byte, rest::binary>> = binary
    assert Codec.decode_frames(<<head::binary, Bitwise.bxor(byte, 1), rest::binary>>) == [:first]

    assert Codec.decode_frames("") == []
  end
end
