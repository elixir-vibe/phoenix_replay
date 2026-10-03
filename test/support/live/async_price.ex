defmodule PhoenixReplay.Test.Live.AsyncPrice do
  @moduledoc "Component that loads its state with assign_async and start_async."

  use Phoenix.LiveComponent

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(total: nil, clicks: 0)
     |> assign_async(:price, fn -> {:ok, %{price: 42}} end)
     |> start_async(:total, fn -> 100 end)}
  end

  @impl true
  def handle_async(:total, {:ok, total}, socket), do: {:noreply, assign(socket, total: total)}

  @impl true
  def handle_event("click", _params, socket), do: {:noreply, update(socket, :clicks, &(&1 + 1))}

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <span :if={@price.ok?} class="price">{@price.result}</span>
      <span :if={@total} class="total">{@total}</span>
      <button phx-click="click" phx-target={@myself}>{@clicks}</button>
    </div>
    """
  end
end
