defmodule PhoenixReplay.Test.Live.LayoutPage do
  @moduledoc """
  A view whose `use` names a layout, which `?layout=none` turns off in
  `mount/3`, as a view can.
  """
  use Phoenix.LiveView, layout: {PhoenixReplay.Test.Layouts, :app}

  @impl true
  def mount(%{"layout" => "none"}, _session, socket), do: {:ok, socket, layout: false}
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns), do: ~H"<main>Page</main>"
end
