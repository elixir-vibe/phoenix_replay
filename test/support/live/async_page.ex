defmodule PhoenixReplay.Test.Live.AsyncPage do
  @moduledoc "View rendering a component whose state arrives asynchronously."

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={PhoenixReplay.Test.Live.AsyncPrice} id="price" />
    """
  end
end
