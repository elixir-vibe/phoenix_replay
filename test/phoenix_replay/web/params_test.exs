defmodule PhoenixReplay.Web.ParamsTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Web.Params

  test "parses non-negative integers" do
    assert Params.integer("3", 1) == 3
    assert Params.integer(3, 1) == 3
    assert Params.integer(-3, 1) == 1
    assert Params.integer("-3", 1) == 1
    assert Params.integer("3x", 1) == 1
    assert Params.integer(nil, 1) == 1
  end
end
