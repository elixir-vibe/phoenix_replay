defmodule PhoenixReplay.Capture.PointerTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Capture.Pointer

  test "keeps well-formed moves, presses and scrolls" do
    params = %{
      "span" => 900,
      "m" => [0, 10, 20, 0, 50, 15, 25, 0],
      "p" => [[60, 0, 15, 25, 0, 0, "task-1", 500, 250], [80, 1, 15, 25, 0, 0, nil, 0, 0]],
      "s" => [0, 0, 120]
    }

    assert {:ok, data} = Pointer.parse(params, 500)
    assert data.span == 900
    assert data.moves == [0, 10, 20, 0, 50, 15, 25, 0]

    assert data.presses == [
             [60, 0, 15, 25, 0, 0, "task-1", 500, 250],
             [80, 1, 15, 25, 0, 0, nil, 0, 0]
           ]

    assert data.scrolls == [0, 0, 120]
  end

  test "drops what the browser should not have sent, and caps each batch" do
    # Moves of the wrong length or with anything but integers go whole.
    assert {:ok, %{moves: []}} =
             Pointer.parse(%{"span" => 1, "m" => [0, 1, 2], "s" => [0, 0, 0]}, 10)

    assert {:ok, %{moves: []}} =
             Pointer.parse(%{"span" => 1, "m" => [0, "x", 2, 0], "s" => [0, 0, 0]}, 10)

    # Bad presses go one by one; targets and fractions are bounded.
    press = [1, 0, 1, 1, 0, 0, String.duplicate("a", 500), 5_000, -3]

    assert {:ok, %{presses: [kept]}} =
             Pointer.parse(%{"span" => 1, "p" => [press, [1, 7, 1, 1, 0, 0, nil, 0, 0]]}, 10)

    assert [_dt, 0, 1, 1, 0, 0, target, 1_000, 0] = kept
    assert String.length(target) == 128

    # Coordinates are clamped, and a batch keeps at most max_points entries.
    assert {:ok, %{scrolls: [0, 100_000, 0]}} =
             Pointer.parse(%{"span" => 1, "s" => [0, 10_000_000, 0]}, 10)

    moves = List.flatten(for i <- 1..50, do: [i, i, i, 0])
    assert {:ok, %{moves: kept_moves}} = Pointer.parse(%{"span" => 1, "m" => moves}, 10)
    assert length(kept_moves) == 40

    # Nothing usable, or no span, is no batch.
    assert Pointer.parse(%{"span" => 1}, 10) == :error
    assert Pointer.parse(%{"m" => [0, 1, 2, 0]}, 10) == :error
  end
end
