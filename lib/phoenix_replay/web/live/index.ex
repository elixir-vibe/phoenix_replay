defmodule PhoenixReplay.Web.Live.Index do
  @moduledoc """
  Lists recordings, live sessions first, narrowed by a
  `PhoenixReplay.Recordings.Filter` kept in the URL.

  Refreshes when `PhoenixReplay.Recordings` broadcasts a change, and every
  few seconds while live sessions are shown so their counters advance.
  """

  use Phoenix.LiveView

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.Core

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
    case Enum.find(socket.assigns.recordings, &(&1.id == id and not &1.live?)) do
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

    summaries = Filter.apply(all, socket.assigns.filter, System.system_time(:millisecond))
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
      recordings: recordings,
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
    <main class="mx-auto max-w-4xl px-4 py-8">
      <.flash flash={@flash} />
      <header class="mb-8 flex items-center justify-between">
        <h1 class="flex items-center gap-2 text-2xl font-semibold">
          <.icon name="lucide:circle-play" class="size-6 text-accent" /> PhoenixReplay
        </h1>
        <div class="flex items-center gap-3 text-sm text-muted">
          {Format.count(@total, "recording")}
          <.button
            :if={@can_clear?}
            variant="danger"
            phx-click="clear"
            data-confirm="Delete every recording?"
          >
            Clear all
          </.button>
        </div>
      </header>

      <form
        :if={@any?}
        id="recording-filter"
        phx-change="filter"
        phx-submit="filter"
        class="mb-6 grid grid-cols-2 gap-2 text-sm sm:grid-cols-7"
      >
        <input
          type="search"
          name="q"
          value={@filter.query}
          placeholder="URL or id"
          aria-label="Search by URL or id"
          phx-debounce="300"
          class="col-span-2 rounded-md border border-line bg-surface px-3 py-1.5 placeholder:text-faint"
        />
        <select
          name="view"
          aria-label="View"
          class="rounded-md border border-line bg-surface px-2 py-1.5"
        >
          <option value="">All views</option>
          <option :for={view <- @views} value={view} selected={view == @filter.view}>{view}</option>
        </select>
        <input
          type="text"
          name="event"
          value={@filter.event}
          list="recording-filter-events"
          placeholder="Event name"
          aria-label="Triggered event"
          phx-debounce="300"
          class="rounded-md border border-line bg-surface px-3 py-1.5 placeholder:text-faint"
        />
        <datalist id="recording-filter-events">
          <option :for={name <- @event_names} value={name} />
        </datalist>
        <select
          name="within"
          aria-label="Started within"
          class="rounded-md border border-line bg-surface px-2 py-1.5"
        >
          <option value="">Any time</option>
          <option
            :for={window <- Filter.windows()}
            value={window}
            selected={window == @filter.within}
          >
            Last {window}
          </option>
        </select>
        <input
          type="number"
          name="min_events"
          min="1"
          value={@filter.min_events}
          placeholder="Min events"
          aria-label="Minimum events"
          phx-debounce="300"
          class="rounded-md border border-line bg-surface px-3 py-1.5 placeholder:text-faint"
        />
        <label class="flex items-center gap-2 rounded-md border border-line bg-surface px-3 py-1.5">
          <input
            type="checkbox"
            name="errors"
            value="1"
            checked={@filter.errors}
            class="accent-accent"
          /> Errors
        </label>
      </form>

      <.empty_state :if={@any? and @recordings == []} title="No recordings match these filters.">
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

      <ul class="space-y-3">
        <li
          :for={recording <- @recordings}
          id={"recording-#{recording.id}"}
          class="flex items-center justify-between gap-4 rounded-lg border border-line bg-surface px-5 py-4 transition-shadow hover:shadow-md"
        >
          <div class="min-w-0">
            <p class="flex items-center gap-2 font-medium">
              <span class="truncate">{recording.view}</span>
              <.badge :if={recording.live?} tone="live" dot="pulse">LIVE</.badge>
            </p>
            <p class="mt-1 flex flex-wrap items-center gap-x-1 text-sm text-muted tabular-nums">
              {Format.timestamp(recording.connected_at)} · {Format.count(
                recording.event_count,
                "event"
              )} · {Format.duration(recording.duration_ms)}
              <span :if={recording.error_count > 0} class="text-error">
                · {Format.count(recording.error_count, "error")}
              </span>
            </p>
          </div>
          <div class="flex shrink-0 items-center gap-3">
            <code class="font-mono text-sm text-faint">{String.slice(recording.id, 0, 8)}</code>
            <.link
              navigate={Context.path(@context, [recording.id])}
              class="inline-flex h-8 items-center rounded-md border border-line px-2.5 text-xs font-medium hover:bg-hover"
            >
              Open
            </.link>
            <.button
              :if={!recording.live?}
              variant="danger"
              phx-click="delete"
              phx-value-id={recording.id}
              data-confirm="Delete this recording?"
            >
              Delete
            </.button>
          </div>
        </li>
      </ul>

      <.pagination
        page={@page}
        total_pages={@total_pages}
        path={&index_path(@context, @filter, &1)}
      />
    </main>
    """
  end
end
