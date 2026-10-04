defmodule ExampleWeb.Catalog.Live do
  @moduledoc """
  Shows every PhoenixReplay dashboard component in each of its states, in
  light and dark, for keeping the dashboard consistent while it changes.
  Mounted only with `dev_routes`.

  The dashboard stylesheet is built from the library's sources alone, so this
  page uses only classes the dashboard already does.
  """

  use Phoenix.LiveView

  import PhoenixReplay.Web.Components.Core
  import PhoenixReplay.Web.Components.Player, only: [event_icon: 1]

  alias Phoenix.LiveView.JS

  @event_types ~w(mount event params info render component telemetry log exit viewport)a

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Components",
       mode: "fit",
       pressed: true,
       event_types: @event_types
     )}
  end

  @impl true
  def handle_event("mode", %{"value" => mode}, socket),
    do: {:noreply, assign(socket, :mode, mode)}

  def handle_event("chip", _params, socket), do: {:noreply, update(socket, :pressed, &(not &1))}

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto flex max-w-4xl flex-col gap-4 px-4 py-8">
      <header class="flex items-center justify-between gap-4">
        <h1 class="text-2xl font-semibold">Components</h1>
        <div role="group" aria-label="Theme" class="flex gap-1">
          <.button phx-click={JS.remove_attribute("data-theme", to: "html")}>System</.button>
          <.button phx-click={JS.set_attribute({"data-theme", "light"}, to: "html")}>Light</.button>
          <.button phx-click={JS.set_attribute({"data-theme", "dark"}, to: "html")}>Dark</.button>
        </div>
      </header>

      <.panel title="Buttons" padded>
        <div class="flex flex-wrap items-center gap-2">
          <.button variant="primary">Primary</.button>
          <.button>Secondary</.button>
          <.button variant="danger">
            <PhoenixIconify.icon name="lucide:trash-2" class="size-3.5" /> Delete
          </.button>
          <.button variant="ghost">Ghost</.button>
          <.button disabled>Disabled</.button>
          <.button size="md">Medium</.button>
          <.icon_button label="Play"><PhoenixIconify.icon name="lucide:play" class="size-4" /></.icon_button>
          <.icon_button label="Next" variant="ghost">
            <PhoenixIconify.icon name="lucide:skip-forward" class="size-4" />
          </.icon_button>
        </div>
      </.panel>

      <.panel title="Status" padded>
        <div class="flex flex-wrap items-center gap-2">
          <.badge>neutral</.badge>
          <.badge tone="live" dot="pulse">LIVE</.badge>
          <.badge tone="error" dot="static">2 errors</.badge>
          <.chip pressed={@pressed} phx-click="chip">Telemetry</.chip>
          <.segmented
            label="Frame size"
            options={[{"fit", "Fit"}, {"actual", "100%"}]}
            value={@mode}
            event="mode"
          />
        </div>
        <div class="mt-4 max-w-sm">
          <.progress label="Redaction" value={42.0} />
        </div>
      </.panel>

      <.panel title="Event types" padded>
        <ul class="flex flex-wrap gap-x-3 gap-y-1 text-sm">
          <li :for={type <- @event_types} class="flex items-center gap-2 text-muted">
            <.event_icon type={type} /> {type}
          </li>
        </ul>
      </.panel>

      <.panel title="Data list" padded>
        <.data_list>
          <:item title="utm_source">hackernews</:item>
          <:item title="accept-language">en-US,en;q=0.9</:item>
        </.data_list>
      </.panel>

      <.panel title="Pagination" padded>
        <div class="flex flex-col gap-2">
          <.pagination page={1} total_pages={3} path={&"?page=#{&1}"} />
          <.pagination page={5} total_pages={12} path={&"?page=#{&1}"} />
        </div>
      </.panel>

      <.panel title="Empty state">
        <.empty_state title="No recordings yet.">
          <:icon><PhoenixIconify.icon name="lucide:video" class="size-10" /></:icon>
          Use your app with recording on.
          <:action><.button>Refresh</.button></:action>
        </.empty_state>
      </.panel>
    </main>
    """
  end
end
