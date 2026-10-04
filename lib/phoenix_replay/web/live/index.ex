defmodule PhoenixReplay.Web.Live.Index do
  @moduledoc """
  Lists recordings, live sessions first, narrowed by a
  `PhoenixReplay.Recordings.Filter` kept in the URL.

  Refreshes when `PhoenixReplay.Recordings` broadcasts a change, and every
  few seconds while live sessions are shown so their counters advance.
  """

  use Phoenix.LiveView

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.{Core, Recordings}

  alias PhoenixReplay.Recordings
  alias PhoenixReplay.Recordings.Filter
  alias PhoenixReplay.Web.{Context, Format, Layouts, Params}

  @per_page 25
  @live_refresh_ms 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Recordings.subscribe()
    context = Context.fetch(socket)

    {:ok,
     assign(socket,
       page_title: "PhoenixReplay",
       assets: Layouts.dashboard_assets(context),
       context: context,
       page: 1,
       filter: %Filter{},
       refresh_timer: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(page: Params.integer(params["page"], 1), filter: Filter.from_params(params))
     |> load()}
  end

  @impl true
  def handle_info(message, socket) when message in [:recordings_changed, :refresh] do
    {:noreply, load(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.saved, &(&1.id == id)) do
      nil -> {:noreply, socket}
      summary -> {:noreply, perform(socket, :delete, summary, &Recordings.delete(&1, id))}
    end
  end

  def handle_event("filter", params, socket) do
    path = index_path(socket.assigns.context, Filter.from_params(params), 1)
    {:noreply, push_patch(socket, to: path, replace: true)}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, perform(socket, :clear, nil, &Recordings.clear/1)}
  end

  defp perform(socket, action, subject, fun) do
    with true <- Context.allowed?(socket, action, subject),
         :ok <- fun.(socket.assigns.context.config) do
      load(socket)
    else
      false ->
        socket

      {:error, reason} ->
        socket |> put_flash(:error, "Could not #{action}: #{inspect(reason)}") |> load()
    end
  end

  defp load(socket) do
    all =
      socket.assigns.context.config
      |> Recordings.list()
      |> Enum.filter(&Context.allowed?(socket, :list, &1))

    now = System.system_time(:millisecond)
    summaries = Filter.apply(all, socket.assigns.filter, now)
    total = length(summaries)
    total_pages = max(1, ceil(total / @per_page))
    page = min(socket.assigns.page, total_pages)
    recordings = Enum.slice(summaries, (page - 1) * @per_page, @per_page)

    socket
    |> assign(
      page: page,
      total_pages: total_pages,
      total: total,
      any?: all != [],
      now: now,
      live: Enum.filter(recordings, & &1.live?),
      saved: Enum.reject(recordings, & &1.live?),
      counts: %{
        all: length(all),
        live: Enum.count(all, & &1.live?),
        errors: Enum.count(all, &(&1.error_count > 0))
      },
      views: all |> Enum.map(& &1.view) |> Enum.uniq() |> Enum.sort(),
      event_names: all |> Enum.flat_map(& &1.event_names) |> Enum.uniq() |> Enum.sort(),
      can_clear?: all != [] and Context.allowed?(socket, :clear, nil)
    )
    |> schedule_refresh(Enum.any?(recordings, & &1.live?))
  end

  defp schedule_refresh(%{assigns: %{refresh_timer: timer}} = socket, live?) do
    if timer, do: Process.cancel_timer(timer)

    timer =
      if live? and connected?(socket), do: Process.send_after(self(), :refresh, @live_refresh_ms)

    assign(socket, :refresh_timer, timer)
  end

  defp index_path(context, filter, page) do
    params = Filter.to_params(filter)
    params = if page > 1, do: Map.put(params, "page", Integer.to_string(page)), else: params

    case URI.encode_query(params) do
      "" -> Context.path(context, [])
      query -> Context.path(context, []) <> "?" <> query
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app_bar>
      <:mark><.icon name="lucide:circle-play" class="size-5 text-accent" /></:mark>
      <:crumb>PhoenixReplay</:crumb>
      <:crumb>Recordings</:crumb>
      <:actions>
        <a
          href="https://hexdocs.pm/phoenix_replay"
          class="hidden rounded-md px-2.5 py-2 text-sm text-muted hover:text-ink sm:block"
        >
          Docs
        </a>
        <.menu :if={@can_clear?} id="recordings-menu" label="More actions">
          <:trigger><.icon name="lucide:ellipsis" class="size-4" /></:trigger>
          <:item tone="danger">
            <button type="button" phx-click="clear" data-confirm="Delete every recording?">
              <.icon name="lucide:trash-2" class="size-4" /> Delete all recordings
            </button>
          </:item>
        </.menu>
      </:actions>
    </.app_bar>

    <main class="mx-auto max-w-6xl px-4 py-8 sm:px-6">
      <.flash flash={@flash} />
      <header class="mb-5">
        <h1 class="text-2xl font-semibold tracking-tight">Recordings</h1>
        <p :if={@any?} class="mt-1.5 text-sm text-muted">
          {Format.count(@counts.all, "session")} · {@counts.live} live · {@counts.errors} with errors
        </p>
      </header>

      <.filter_bar :if={@any?} filter={@filter} views={@views} event_names={@event_names} />

      <.empty_state :if={@any? and @total == 0} title="No recordings match these filters.">
        <:icon><.icon name="lucide:search-x" class="size-8" /></:icon>
        <:action>
          <.link
            patch={index_path(@context, %Filter{}, 1)}
            class="text-sm text-muted underline hover:text-ink"
          >
            Clear filters
          </.link>
        </:action>
      </.empty_state>

      <.empty_state :if={not @any?} title="No recordings yet.">
        <:icon><.icon name="lucide:video" class="size-10" /></:icon>
        Add <code class="font-mono text-ink">on_mount: [PhoenixReplay.Recorder]</code>
        to a <code class="font-mono text-ink">live_session</code>
        and use your app.
      </.empty_state>

      <.recording_list live recordings={@live} now={@now} path={&Context.path(@context, [&1.id])} />
      <.recording_list
        recordings={@saved}
        now={@now}
        path={&Context.path(@context, [&1.id])}
        delete="delete"
      />

      <div class="mt-6">
        <.pagination
          page={@page}
          total_pages={@total_pages}
          path={&index_path(@context, @filter, &1)}
        />
      </div>
    </main>
    """
  end
end
