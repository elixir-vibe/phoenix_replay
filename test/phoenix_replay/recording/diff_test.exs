defmodule PhoenixReplay.Web.Player.DiffTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording.Diff

  defmodule Task do
    defstruct [:id, :title, done: false]
  end

  test "names nothing when nothing changed" do
    assert Diff.changes(%{a: [1, 2]}, %{a: [1, 2]}) == []
  end

  test "walks maps, structs and tuples to the values that changed" do
    before = %{user: %{name: "Ann", roles: {:admin, :ops}}, count: 1}
    after_value = %{user: %{name: "Ann", roles: {:admin, :dev}}, count: 2, new: true}

    assert Diff.changes(before, after_value) == [
             {:changed, [key: :count], 1, 2},
             {:added, [key: :new], true},
             {:changed, [key: :user, key: :roles, index: 1], :ops, :dev}
           ]

    assert Diff.changes(%Task{id: 1}, %Task{id: 1, done: true}) == [
             {:changed, [key: :done], false, true}
           ]

    # Timestamps and the like change whole.
    assert [{:changed, [key: :at], ~U[2026-10-05 09:56:00Z], ~U[2026-10-05 10:06:00Z]}] =
             Diff.changes(%{at: ~U[2026-10-05 09:56:00Z]}, %{at: ~U[2026-10-05 10:06:00Z]})

    # A different kind of value is one change, not a walk.
    assert [{:changed, [], %Task{}, %{id: 1}}] = Diff.changes(%Task{id: 1}, %{id: 1})
  end

  test "matches list items by id, wherever they moved" do
    before = [%Task{id: 1, title: "a"}, %Task{id: 2, title: "b"}, %Task{id: 3, title: "c"}]

    after_value = [
      %Task{id: 2, title: "b", done: true},
      %Task{id: 1, title: "a"},
      %Task{id: 4, title: "d"}
    ]

    assert [
             {:changed, [id: 2, key: :done], false, true},
             {:removed, [id: 3], %Task{id: 3}},
             {:added, [id: 4], %Task{id: 4}}
           ] = Diff.changes(before, after_value)
  end

  test "matches list items by position without ids" do
    assert Diff.changes([1, 2, 3], [1, 5]) == [
             {:changed, [index: 1], 2, 5},
             {:removed, [index: 2], 3}
           ]

    # Repeated ids are not ids to match on.
    assert [{:changed, [index: 1, key: :title], "b", "c"}] =
             Diff.changes([%{id: 1, title: "a"}, %{id: 1, title: "b"}], [
               %{id: 1, title: "a"},
               %{id: 1, title: "c"}
             ])
  end

  test "writes paths as Elixir-like access" do
    assert Diff.path(:tasks, id: "0f4e", key: :done) == ~s(tasks[id: "0f4e"].done)
    assert Diff.path(:form, key: "email", index: 2) == ~s(form["email"][2])

    assert Diff.path(:tasks, id: "0f4e6d12-073b-4805-96ca-720262628371") ==
             ~s(tasks[id: "0f4e6d12…"])
  end

  test "marks the changed lines of the pretty-printed values, folding the rest" do
    before = %{a: 1, list: Enum.to_list(1..30)}
    after_value = %{before | a: 2}

    assert [{:skip, _count} | rest] = Diff.lines(before, after_value, width: 20)
    assert {:del, "  a: 1"} in rest
    assert {:ins, "  a: 2"} in rest
    assert Diff.lines(:same, :same) == [{:skip, 1}]
  end
end
