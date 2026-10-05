defmodule ExampleWeb.Catalog.Live do
  @moduledoc """
  Shows every PhoenixReplay dashboard component in each of its states, in
  light and dark, for keeping the dashboard consistent while it changes.
  Mounted only with `dev_routes`.

  The dashboard stylesheet is built from the library's sources alone, so this
  page uses only classes the dashboard already does.
  """

  use Phoenix.LiveView

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.Core
  import PhoenixReplay.Web.Components.Player, only: [event_icon: 1]
  import PhoenixReplay.Web.Components.Recordings

  alias Phoenix.LiveView.JS
  alias PhoenixReplay.Recording.{Client, Summary}
  alias PhoenixReplay.Recordings.Filter

  @event_types ~w(mount event params info render component telemetry log exit viewport)a

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Components",
       mode: "fit",
       pressed: true,
       tab: "events",
       event_types: @event_types,
       now: System.system_time(:millisecond),
       summaries: summaries()
     )}
  end

  # A live session, a saved one from a phone with a campaign, and a desktop
  # one with errors.
  defp summaries do
    now = System.system_time(:millisecond)

    summary = fn id, attrs ->
      struct!(
        %Summary{
          id: id,
          view: "ExampleWeb.TaskLive.Index",
          url: "http://localhost/",
          connected_at: now
        },
        attrs
      )
    end

    [
      summary.("live000000",
        live?: true,
        duration_ms: 12_000,
        event_count: 16,
        connected_at: now - 12_000
      ),
      summary.("phone00000",
        connected_at: now - 120_000,
        duration_ms: 41_000,
        event_count: 25,
        viewport: Client.decode_viewport("390x844@3"),
        device: "Mobile Safari 18 on iOS",
        source: "hackernews / social"
      ),
      summary.("desk000000",
        connected_at: now - 11 * 3_600_000,
        duration_ms: 10_000,
        event_count: 95,
        error_count: 2,
        url: "http://localhost/tasks/new",
        viewport: Client.decode_viewport("1440x900@2"),
        device: "Chrome 141 on Mac OS X"
      )
    ]
  end

  @impl true
  def handle_event("mode", %{"value" => mode}, socket),
    do: {:noreply, assign(socket, :mode, mode)}

  def handle_event("chip", _params, socket), do: {:noreply, update(socket, :pressed, &(not &1))}

  def handle_event("tab", %{"value" => tab}, socket), do: {:noreply, assign(socket, :tab, tab)}

  # The list components' own events do nothing here.
  def handle_event(event, _params, socket) when event in ~w(filter show_new delete clear),
    do: {:noreply, socket}

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

      <.panel title="App bar and menu">
        <.app_bar>
          <:mark><.icon name="lucide:circle-play" class="size-5 text-accent" /></:mark>
          <:crumb>PhoenixReplay</:crumb>
          <:crumb>Recordings</:crumb>
          <:actions>
            <.menu id="catalog-menu" label="More actions">
              <:trigger><.icon name="lucide:ellipsis" class="size-4" /></:trigger>
              <:item tone="danger">
                <button type="button" phx-click="clear">
                  <.icon name="lucide:trash-2" class="size-4" /> Delete all recordings
                </button>
              </:item>
            </.menu>
          </:actions>
        </.app_bar>
      </.panel>

      <.panel title="Tabs">
        <.tabs
          id="catalog-tabs"
          label="Session details"
          tabs={[{"events", "Events"}, {"state", "State"}, {"visit", "Visit"}]}
          value={@tab}
          event="tab"
        />
        <p id="catalog-tabs-panel" role="tabpanel" class="p-4 text-sm text-muted">{@tab}</p>
      </.panel>

      <.panel title="Recording list" padded>
        <.filter_bar
          filter={%Filter{errors: true}}
          path={&("?" <> URI.encode_query(Filter.to_params(&1)))}
          views={["ExampleWeb.TaskLive.Index"]}
          event_names={["save"]}
        />
        <.new_recordings count={3} />
        <.recording_list
          live
          recordings={Enum.filter(@summaries, & &1.live?)}
          now={@now}
          path={&("#" <> &1.id)}
        />
        <.recording_list
          recordings={Enum.reject(@summaries, & &1.live?)}
          now={@now}
          path={&("#" <> &1.id)}
          delete="delete"
        />
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
