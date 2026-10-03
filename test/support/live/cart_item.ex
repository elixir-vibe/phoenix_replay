defmodule PhoenixReplay.Test.Live.CartItem do
  @moduledoc "Component that keeps its own quantity."

  use Phoenix.LiveComponent

  @impl true
  def mount(socket), do: {:ok, assign(socket, quantity: 0)}

  @impl true
  def handle_event("add", _params, socket), do: {:noreply, update(socket, :quantity, &(&1 + 1))}

  @impl true
  def render(assigns) do
    ~H"""
    <li id={"item-#{@id}"}>
      {@name}: <span class="quantity">{@quantity}</span>
      <button phx-click="add" phx-target={@myself}>Add</button>
    </li>
    """
  end
end
