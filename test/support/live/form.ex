defmodule PhoenixReplay.Test.Live.Form do
  @moduledoc "Form view recorded in tests, with a sensitive field."

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, name: "", password: "")}

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, name: params["name"], password: params["password"])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form id="form" phx-change="validate">
      <input type="text" name="name" value={@name} />
      <input type="password" name="password" value={@password} />
      <span id="greeting">Hello {String.upcase(@name)}</span>
    </form>
    """
  end
end
