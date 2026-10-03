defmodule PhoenixReplay.Test.Live.Embedded do
  @moduledoc "View that records itself with a module-level on_mount, as live_render/3 children do."

  use Phoenix.LiveView

  on_mount PhoenixReplay.Recorder

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0)}

  @impl true
  def handle_event("inc", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}

  @impl true
  def render(assigns) do
    ~H"""
    <button phx-click="inc">{@count}</button>
    """
  end
end
