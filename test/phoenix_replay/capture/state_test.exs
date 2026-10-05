defmodule PhoenixReplay.Capture.StateTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Capture.State
  alias PhoenixReplay.Config
  alias PhoenixReplay.Sanitizer.Default

  @state Config.new([]).state

  defp parse(params, state \\ @state), do: State.parse(params, state, Default)

  test "keeps entries with a key and a JSON object, sanitized" do
    assert {:ok,
            %{span: 10, entries: [[0, "form", %{"name" => "Ann", "password" => "[FILTERED]"}]]}} =
             parse(%{"span" => 10, "e" => [[0, "form", %{"name" => "Ann", "password" => "x"}]]})
  end

  test "drops malformed entries, and a batch with none left" do
    entries = [
      [0, "", %{}],
      [0, :atom, %{}],
      [0, "k", [1, 2]],
      [0, "k", "text"],
      ["0", "k", %{}],
      [0, "k"],
      "entry",
      [5, "ok", %{"a" => 1}]
    ]

    assert {:ok, %{entries: [[5, "ok", %{"a" => 1}]]}} = parse(%{"span" => 5, "e" => entries})
    assert parse(%{"span" => 5, "e" => [[0, "", %{}]]}) == :error
    assert parse(%{"span" => -1, "e" => [[0, "k", %{}]]}) == :error
    assert parse(%{"e" => [[0, "k", %{}]]}) == :error
    assert parse(%{"span" => 0, "e" => %{}}) == :error
  end

  test "bounds keys, entries, sizes and nesting" do
    state = %{@state | max_key: 3, max_entries: 2, max_entry_bytes: 20, max_bytes: 30}
    small = %{"a" => 1}

    assert {:ok, %{entries: [[0, "abc", _]]}} =
             parse(%{"span" => 0, "e" => [[0, "abcd", small], [0, "abc", small]]}, state)

    # Only the first max_entries are read.
    assert {:ok, %{entries: [_, _]}} =
             parse(%{"span" => 0, "e" => List.duplicate([0, "k", small], 5)}, state)

    # An entry over max_entry_bytes is dropped; the batch stops at max_bytes.
    big = %{"a" => String.duplicate("x", 30)}
    medium = %{"a" => String.duplicate("x", 10)}

    assert {:ok, %{entries: [[0, "k", ^medium]]}} =
             parse(
               %{"span" => 0, "e" => [[0, "k", big], [0, "k", medium], [0, "k", medium]]},
               state
             )

    deep = Enum.reduce(1..40, %{}, fn _level, acc -> %{"a" => acc} end)
    assert parse(%{"span" => 0, "e" => [[0, "k", deep]]}) == :error
  end

  test "clamps times" do
    assert {:ok, %{span: 60_000, entries: [[0, "k", _], [60_000, "k", _]]}} =
             parse(%{"span" => 10_000_000, "e" => [[-5, "k", %{}], [10_000_000, "k", %{}]]})
  end

  test "creates no atoms from what the browser sends" do
    key = "phoenix_replay_state_key_#{System.unique_integer([:positive])}"
    assert {:ok, _batch} = parse(%{"span" => 0, "e" => [[0, key, %{key => key}]]})
    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
  end
end
