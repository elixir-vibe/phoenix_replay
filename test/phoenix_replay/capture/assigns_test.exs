defmodule PhoenixReplay.Capture.AssignsTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Capture.Assigns
  alias PhoenixReplay.Sanitizer.Default

  defmodule KeepAll do
    @behaviour PhoenixReplay.Sanitizer

    @impl true
    def sanitize_assigns(assigns), do: assigns

    @impl true
    def sanitize_params(params), do: params
  end

  @assigns %{__changed__: %{}, uploads: %{}, streams: %{}, flash: %{}, myself: 1, count: 1}

  test "drops LiveView internals before any sanitizer sees them" do
    assert Assigns.view(@assigns, KeepAll) == %{flash: %{}, myself: 1, count: 1}
    assert Assigns.component(@assigns, KeepAll) == %{count: 1}
  end

  test "sanitizes what it keeps" do
    assert Assigns.view(%{token: "t"}, Default) == %{token: "[FILTERED]"}
  end
end
