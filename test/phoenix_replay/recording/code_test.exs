defmodule PhoenixReplay.Recording.CodeTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording.Code
  alias PhoenixReplay.Test.Live.{Cart, CartItem, Counter}

  test "records the view's code, its release and the dependencies that render" do
    code = Code.of(Counter, nil)

    assert code.release == Application.spec(:phoenix_replay, :vsn) |> List.to_string()
    assert %{Counter => md5} = code.modules
    assert md5 == Counter.module_info(:md5) |> Base.encode16(case: :lower)
    assert Map.has_key?(code.deps, :phoenix_live_view)
    refute Map.has_key?(code.deps, :jason)

    assert Code.of(Counter, "abc123").release == "abc123"
    assert Code.changes(code) == %{modules: [], deps: []}
  end

  test "adds the LiveComponents a session rendered" do
    code = Cart |> Code.of(nil) |> Code.with_modules([CartItem])
    assert Map.keys(code.modules) |> Enum.sort() == [Cart, CartItem]
    assert Code.with_modules(nil, [CartItem]) == nil
  end

  test "tells which modules and dependencies changed since" do
    code = %{
      Code.of(Counter, nil)
      | modules: %{Counter => "0", Cart => Code.of(Cart, nil).modules[Cart], Gone => "1"}
    }

    code = put_in(code.deps[:phoenix_live_view], "0.0.1")

    assert %{modules: [Gone, Counter], deps: [{:phoenix_live_view, "0.0.1", now}]} =
             Code.changes(code)

    assert now == Application.spec(:phoenix_live_view, :vsn) |> List.to_string()
    assert Code.changes(nil) == %{modules: [], deps: []}
  end
end
