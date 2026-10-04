defmodule PhoenixReplay.Web.Components.Player do
  @moduledoc """
  Components of the player that know about recordings and their events.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]

  @doc "The icon for an event's type."
  attr :type, :atom, required: true, doc: "a `PhoenixReplay.Recording.Event` type"
  attr :class, :any, default: "size-3.5"

  @spec event_icon(map()) :: Phoenix.LiveView.Rendered.t()
  def event_icon(assigns) do
    ~H"""
    <%= case @type do %>
      <% :mount -> %>
        <.icon name="lucide:rocket" class={@class} />
      <% :event -> %>
        <.icon name="lucide:mouse-pointer-click" class={@class} />
      <% :params -> %>
        <.icon name="lucide:link" class={@class} />
      <% :info -> %>
        <.icon name="lucide:mail" class={@class} />
      <% :render -> %>
        <.icon name="lucide:pencil-line" class={@class} />
      <% type when type in [:component, :component_destroyed] -> %>
        <.icon name="lucide:puzzle" class={@class} />
      <% :telemetry -> %>
        <.icon name="lucide:activity" class={@class} />
      <% :log -> %>
        <.icon name="lucide:message-square-text" class={@class} />
      <% :exit -> %>
        <.icon name="lucide:octagon-x" class={@class} />
      <% :viewport -> %>
        <.icon name="lucide:scaling" class={@class} />
    <% end %>
    """
  end
end
