defmodule PhoenixReplay.Web.RenderingTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Web.Rendering

  test "describes a missing assign without dumping every assign" do
    assigns = %{__changed__: %{}, tasks: List.duplicate("task", 500)}

    assert Rendering.describe(%KeyError{key: :filter, term: assigns}) ==
             "the recording has no @filter"

    assert Rendering.describe(%KeyError{key: :name, term: %{other: 1}}) ==
             "key :name not found"
  end

  test "keeps the first line of other messages, shortened" do
    assert Rendering.describe(%RuntimeError{message: "boom\nmore detail"}) == "boom"

    assert %RuntimeError{message: String.duplicate("x", 500)}
           |> Rendering.describe()
           |> String.length() == 201
  end
end
