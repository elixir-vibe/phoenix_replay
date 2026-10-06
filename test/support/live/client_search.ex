defmodule PhoenixReplay.Test.Live.ClientSearch do
  @moduledoc """
  A view whose search box lives in the browser, as a client-side component
  would: the server never sees the query, so its replay reads the state the
  browser reported.
  """

  use Phoenix.LiveView
  @behaviour PhoenixReplay.Replayable

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, title: "Shop", query: nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <h1>{@title}</h1>
    <div id="search" phx-update="ignore"></div>
    """
  end

  @doc """
  Renders the search box as the browser reported it, deriving `@query`
  from the reported state as views typically do.
  """
  @impl PhoenixReplay.Replayable
  def replay_render(assigns) do
    assigns = assign(assigns, :query, get_in(assigns.phoenix_replay_state, ["search", "query"]))

    ~H"""
    <h1>{@title}</h1>
    <div id="search">
      <input value={@query} />
      <span id="page">{@phoenix_replay_state["search"]["page"]}</span>
    </div>
    """
  end
end
