defmodule PhoenixReplay.Test.Live.Cart do
  @moduledoc "View whose state lives in LiveComponents."

  use Phoenix.LiveView

  alias PhoenixReplay.Test.Live.CartItem

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, items: ~w(apple pear))}

  @impl true
  def handle_event("remove", %{"item" => item}, socket),
    do: {:noreply, update(socket, :items, &List.delete(&1, item))}

  @impl true
  def render(assigns) do
    ~H"""
    <ul>
      <.live_component :for={item <- @items} module={CartItem} id={item} name={item} />
    </ul>
    """
  end
end
