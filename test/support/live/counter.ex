defmodule PhoenixReplay.Test.Live.Counter do
  @moduledoc "Counter view recorded in tests."

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0)}

  @impl true
  def handle_event("inc", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
  def handle_event("dec", _params, socket), do: {:noreply, update(socket, :count, &(&1 - 1))}
  def handle_event("notify", _params, socket), do: {:noreply, put_flash(socket, :info, "Saved")}

  @impl true
  def handle_info(:reset, socket), do: {:noreply, assign(socket, count: 0)}

  @impl true
  def render(assigns) do
    ~H"""
    <p :if={msg = Phoenix.Flash.get(@flash, :info)} id="flash">{msg}</p>
    <span id="count">{@count}</span>
    <button phx-click="inc">+</button>
    <button phx-click="dec">-</button>
    """
  end
end
