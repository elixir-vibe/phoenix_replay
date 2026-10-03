defmodule PhoenixReplay.AuthorizationTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Authorization
  alias PhoenixReplay.Test.Authorization, as: TestAuthorization

  @socket %Phoenix.LiveView.Socket{}

  test "allows everything without a module" do
    assert Authorization.allowed?(nil, :clear, nil, @socket)
  end

  test "delegates to the module" do
    assert Authorization.allowed?(TestAuthorization, :view, %{id: "public"}, @socket)
    refute Authorization.allowed?(TestAuthorization, :view, %{id: "secret-1"}, @socket)
    refute Authorization.allowed?(TestAuthorization, :clear, nil, @socket)
  end
end
