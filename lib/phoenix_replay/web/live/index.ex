defmodule PhoenixReplay.Web.Live.Index do
  @moduledoc """
  Lists recordings, live sessions first, narrowed by a
  `PhoenixReplay.Recordings.Filter` kept in the URL.

  Reads storage again when `PhoenixReplay.Recordings` broadcasts a change,
  at most once a second however many sessions start and end, and reads the
  buffer every few seconds while live sessions are shown, so their counters
  advance.

  Saved recordings are listed as of a moment, `until`, taken when the list
  opens or its filter changes, so pages stay put while sessions end. Newer
  ones are counted in a banner that brings the list up to date.
  """

  use Phoenix.LiveView

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.{Core, Recordings}

  alias PhoenixReplay.Recordings
  alias PhoenixReplay.Recordings.Filter
  alias PhoenixReplay.Web.{Context, Format, Layouts, Params}

  @per_page 25
  @live_refresh_ms 2_000
  @reload_window_ms 1_000

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
       until: nil,
       refresh_timer: nil,
       reload_window: nil,
       reload?: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = Filter.from_params(params)

    until =
      if filter == socket.assigns.filter and socket.assigns.until,
        do: socket.assigns.until,
        else: System.system_time(:millisecond)

    {:noreply,
     socket
     |> assign(page: max(Params.integer(params["page"], 1), 1), filter: filter, until: until)
     |> load()}
  end

  @impl true
  # The first change reloads at once; changes within the next second
  # reload once more when it is over.
  def handle_info(:recordings_changed, %{assigns: %{reload_window: nil}} = socket),
    do: {:noreply, reload(socket)}

  def handle_info(:recordings_changed, socket), do: {:noreply, assign(socket, :reload?, true)}

  def handle_info(:reload_window, %{assigns: %{reload?: true}} = socket),
    do: {:noreply, reload(socket)}

  def handle_info(:reload_window, socket), do: {:noreply, assign(socket, :reload_window, nil)}

  def handle_info(:refresh, socket), do: {:noreply, load_live(socket)}

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

  def handle_event("show_new", _params, socket) do
    %{context: context, filter: filter} = socket.assigns
    socket = assign(socket, :until, System.system_time(:millisecond))

    if socket.assigns.page == 1,
      do: {:noreply, load(socket)},
      else: {:noreply, push_patch(socket, to: index_path(context, filter, 1))}
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

  defp reload(socket) do
    window = Process.send_after(self(), :reload_window, @reload_window_ms)
    socket |> assign(reload_window: window, reload?: false) |> load()
  end

  defp load(socket), do: socket |> load_stored() |> load_live()

  # What storage holds: the page shown and the counts around it.
  defp load_stored(socket) do
    %{context: %{config: config}} = socket.assigns
    now = System.system_time(:millisecond)
    allow = allow(socket)
    count = &(config |> Recordings.query(&1, now: now, limit: 0, allow: allow) |> elem(1))
    {saved, total, page} = saved_page(socket, now, allow)
    all = count.(%Filter{})

    assign(socket,
      page: page,
      stored: %{saved: saved, total: total, all: all, errors: count.(%Filter{errors: true})},
      newer: newer(socket, now, allow),
      facets: Recordings.facets(config, allow),
      can_clear?: all > 0 and Context.allowed?(socket, :clear, nil)
    )
  end

  # Sessions still in the buffer, running or ended and being saved, merged
  # with the stored page.
  defp load_live(socket) do
    %{filter: filter, page: page, stored: stored} = socket.assigns
    now = System.system_time(:millisecond)

    {live, ending} =
      Recordings.live(%Filter{}, now)
      |> Enum.filter(allow(socket) || fn _summary -> true end)
      |> Enum.split_with(& &1.live?)

    buffered = MapSet.new(live ++ ending, & &1.id)
    shown = Filter.select(live ++ ending, filter, now)

    socket
    |> assign(
      total_pages: max(1, ceil(stored.total / @per_page)),
      total: stored.total + length(shown),
      any?: stored.all + length(live) + length(ending) > 0,
      now: now,
      live: if(page == 1, do: Enum.filter(shown, & &1.live?), else: []),
      saved:
        if(page == 1, do: Enum.reject(shown, & &1.live?), else: []) ++
          Enum.reject(stored.saved, &MapSet.member?(buffered, &1.id)),
      counts: %{
        all: stored.all + length(live) + length(ending),
        live: length(live),
        errors: stored.errors + Enum.count(live ++ ending, &(&1.error_count > 0))
      }
    )
    |> schedule_refresh(live != [])
  end

  # A page of stored recordings, the last one when the requested page is
  # past the end.
  defp saved_page(socket, now, allow) do
    %{context: %{config: config}, filter: filter, page: page} = socket.assigns

    read =
      &Recordings.query(config, filter,
        now: now,
        until: socket.assigns.until,
        offset: (&1 - 1) * @per_page,
        limit: @per_page,
        allow: allow
      )

    case read.(page) do
      {[], total} when page > 1 ->
        last = max(ceil(total / @per_page), 1)
        {saved, total} = read.(last)
        {saved, total, last}

      {saved, total} ->
        {saved, total, page}
    end
  end

  # Saved recordings that started after the list's moment.
  defp newer(socket, now, allow) do
    %{context: %{config: config}, filter: filter, until: until} = socket.assigns

    {_none, count} =
      Recordings.query(config, filter, now: now, since: until, limit: 0, allow: allow)

    count
  end

  # Without an authorization module every recording is listed, and storage
  # pages them; with one, each is checked.
  defp allow(socket) do
    if socket.assigns.context.authorize, do: &Context.allowed?(socket, :list, &1)
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

      <.filter_bar
        :if={@any?}
        filter={@filter}
        views={@facets.views}
        event_names={@facets.event_names}
        path={&index_path(@context, &1, 1)}
      />

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

      <.new_recordings count={@newer} />
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
