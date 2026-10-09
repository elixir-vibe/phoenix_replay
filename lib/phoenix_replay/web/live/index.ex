defmodule PhoenixReplay.Web.Live.Index do
  @moduledoc """
  Lists visits, those still recording first, narrowed by a
  `PhoenixReplay.Recording.Filter` kept in the URL. A visit is listed when
  any of its recordings matches the filter, with all of them; see
  `PhoenixReplay.Recording.Visit`.

  Reads storage again when `PhoenixReplay.Catalog` broadcasts a change,
  at most once a second however many sessions start and end, and reads the
  buffer every few seconds while live sessions are shown, so their counters
  advance.

  Saved recordings are listed as of a moment, `until`, taken when the list
  opens or its filter changes, so pages stay put while sessions end. Newer
  visits are counted in a banner that brings the list up to date.

  Filters beyond the search, the time window and errors are added and
  changed in a value picker, which offers the values recordings have
  with how many have each; see `PhoenixReplay.Web.FilterFields`.
  """

  use Phoenix.LiveView

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.Core
  import PhoenixReplay.Web.Components.Layout
  import PhoenixReplay.Web.Components.Filters, only: [filter_bar: 1]
  import PhoenixReplay.Web.Components.RecordingList

  alias PhoenixReplay.Catalog
  alias PhoenixReplay.Recording.{Filter, Summary, Visit}
  alias PhoenixReplay.Web.{Context, FilterFields, Format, Highlight, Layouts, Params}

  @per_page 25
  # How many values the value picker offers, the most common first.
  @values 50
  @live_refresh_ms 2_000
  @reload_window_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Catalog.subscribe()
    # The player highlights code; the list warms the grammars for it.
    :ok = Highlight.warm()
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
       reload?: false,
       editing: nil,
       values: [],
       typed: "",
       utc_offset: utc_offset(socket)
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
     |> close_filter()
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
  # Deletes the saved recordings of a visit the viewer may delete.
  def handle_event("delete", %{"key" => key}, socket) do
    case Enum.find(socket.assigns.saved, &(&1.key == key)) do
      nil ->
        {:noreply, socket}

      visit ->
        deletable = Enum.filter(visit.recordings, &Context.allowed?(socket, :delete, &1))

        {:noreply,
         perform(socket, :delete, List.first(deletable), fn config ->
           Enum.reduce_while(deletable, :ok, fn summary, :ok ->
             case Catalog.delete(config, summary.id) do
               :ok -> {:cont, :ok}
               error -> {:halt, error}
             end
           end)
         end)}
    end
  end

  # The search; chips keep the other criteria.
  def handle_event("filter", params, socket),
    do: {:noreply, patch_filter(socket, ~w(q), Map.take(params, ~w(q)), replace: true)}

  def handle_event("edit_time", _params, socket),
    do: {:noreply, assign(socket, editing: :time, values: [], typed: "")}

  # A range of start times, in UTC, from the browser.
  def handle_event("time_range", params, socket),
    do: {:noreply, patch_filter(socket, ~w(within from to), Map.take(params, ~w(from to)), [])}

  def handle_event("edit_filter", %{"field" => name}, socket) do
    case FilterFields.parse(name) do
      {:ok, field} -> {:noreply, edit_filter(socket, field)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("type_value", %{"value" => typed}, socket),
    do: {:noreply, assign(socket, :typed, typed)}

  def handle_event("apply_filter", %{"value" => value}, %{assigns: %{editing: %{}}} = socket) do
    %{context: context, filter: filter, editing: field} = socket.assigns
    path = index_path(context, FilterFields.put(filter, field, value), 1)
    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("close_filter", _params, socket), do: {:noreply, close_filter(socket)}

  def handle_event("show_new", _params, socket) do
    %{context: context, filter: filter} = socket.assigns
    socket = assign(socket, :until, System.system_time(:millisecond))

    if socket.assigns.page == 1,
      do: {:noreply, load(socket)},
      else: {:noreply, push_patch(socket, to: index_path(context, filter, 1))}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, perform(socket, :clear, nil, &Catalog.clear/1)}
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

  # The list filtered by `params` in place of the criteria `keys`.
  defp patch_filter(socket, keys, params, opts) do
    filter =
      socket.assigns.filter
      |> Filter.to_params()
      |> Map.drop(keys)
      |> Map.merge(params)
      |> Filter.from_params()

    push_patch(socket, [to: index_path(socket.assigns.context, filter, 1)] ++ opts)
  end

  # Opens the value picker for `field`, with the values recordings
  # matching the other criteria have.
  defp edit_filter(socket, field) do
    %{context: %{config: config}, filter: filter} = socket.assigns

    values =
      if field.control == :choice,
        do:
          Catalog.values(config, field.key, filter,
            now: System.system_time(:millisecond),
            limit: @values,
            allow: allow(socket),
            by: :visit
          ),
        else: []

    assign(socket, editing: field, values: values, typed: "")
  end

  defp close_filter(socket), do: assign(socket, editing: nil, values: [], typed: "")

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

    count =
      &(config |> Catalog.query(&1, now: now, limit: 0, allow: allow, by: :visit) |> elem(1))

    {saved, total, page} = saved_page(socket, now, allow)
    all = count.(%Filter{})

    assign(socket,
      page: page,
      stored: %{saved: saved, total: total, all: all, errors: count.(%Filter{errors: true})},
      newer: newer(socket, now, allow),
      activity:
        Catalog.activity(config, socket.assigns.filter,
          now: now,
          allow: allow,
          utc_offset: socket.assigns.utc_offset,
          by: :visit
        ),
      sampling: Format.sampling(config.sample_rate, config.keep),
      can_clear?: all > 0 and Context.allowed?(socket, :clear, nil)
    )
  end

  # Visits with recordings still in the buffer, running or ended and being
  # saved, merged with the stored page: on the first page, a visit with
  # saved recordings too is shown once, with all of them.
  defp load_live(socket) do
    %{filter: filter, page: page, stored: stored} = socket.assigns
    now = System.system_time(:millisecond)

    buffered =
      Catalog.live(%Filter{}, now)
      |> Enum.filter(allow(socket) || fn _summary -> true end)

    buffered_ids = MapSet.new(buffered, & &1.id)
    saved = Enum.reject(stored.saved, &MapSet.member?(buffered_ids, &1.id))
    all = Visit.group(buffered)
    matching = MapSet.new(Filter.select(buffered, filter, now), &Summary.visit_key/1)
    shown = Enum.filter(all, &MapSet.member?(matching, &1.key))
    shown_keys = MapSet.new(shown, & &1.key)

    # Shown visits take the stored recordings of the same visit on this page.
    {shown, saved} =
      if page == 1 do
        {merged, rest} =
          Enum.split_with(saved, &MapSet.member?(shown_keys, Summary.visit_key(&1)))

        {merged |> Enum.concat(Enum.flat_map(shown, & &1.recordings)) |> Visit.group(), rest}
      else
        {shown, saved}
      end

    {live, ending} = Enum.split_with(shown, & &1.live?)
    {live_all, ending_all} = Enum.split_with(all, & &1.live?)

    socket
    |> assign(
      total_pages: max(1, ceil(stored.total / @per_page)),
      total: stored.total + length(shown),
      any?: stored.all + length(all) > 0,
      now: now,
      live: if(page == 1, do: live, else: []),
      saved: if(page == 1, do: ending, else: []) ++ Visit.group(saved),
      counts: %{
        all: stored.all + length(live_all) + length(ending_all),
        live: length(live_all),
        errors: stored.errors + Enum.count(all, &(&1.error_count > 0))
      }
    )
    |> schedule_refresh(live_all != [])
  end

  # A page of stored recordings, the last one when the requested page is
  # past the end.
  defp saved_page(socket, now, allow) do
    %{context: %{config: config}, filter: filter, page: page} = socket.assigns

    read =
      &Catalog.query(config, filter,
        now: now,
        until: socket.assigns.until,
        offset: (&1 - 1) * @per_page,
        limit: @per_page,
        allow: allow,
        by: :visit
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
      Catalog.query(config, filter, now: now, since: until, limit: 0, allow: allow, by: :visit)

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

  # How far the viewer's time zone is ahead of UTC, in milliseconds, as
  # the browser said when it connected; UTC before then.
  defp utc_offset(socket) do
    case connected?(socket) && get_connect_params(socket)["utc_offset"] do
      minutes when is_integer(minutes) and abs(minutes) <= 14 * 60 -> :timer.minutes(minutes)
      _unknown -> 0
    end
  end

  # The list narrowed to sessions started from `from` to `to`.
  defp range_path(context, %Filter{} = filter, {from, to}),
    do: index_path(context, %Filter{filter | within: nil, from: from, to: to}, 1)

  # A visit opens at its first recording.
  defp visit_path(context, %Visit{recordings: [first | _rest]}),
    do: Context.path(context, [first.id])

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
      <:crumb>Visits</:crumb>
      <:actions>
        <a
          href="https://hexdocs.pm/phoenix_replay"
          class="hidden rounded-md px-2.5 py-2 text-sm text-muted hover:text-ink sm:block"
        >
          Docs
        </a>
        <.theme_toggle id="theme-toggle" />
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
        <h1 class="text-2xl font-semibold tracking-tight">Visits</h1>
        <p :if={@any?} class="mt-1.5 text-sm text-muted">
          {Format.count(@counts.all, "visit")} · {@counts.live} live · {@counts.errors} with errors
        </p>
        <p
          :if={@any? and @sampling}
          id="recordings-sampling"
          class="mt-1 flex items-center gap-1.5 text-xs text-muted"
        >
          <.icon name="lucide:info" class="size-3.5 shrink-0" /> {@sampling}
        </p>
      </header>

      <.filter_bar
        :if={@any?}
        filter={@filter}
        path={&index_path(@context, &1, 1)}
        editing={@editing}
        values={@values}
        typed={@typed}
      />

      <.activity_chart
        :if={@any?}
        activity={@activity}
        path={&range_path(@context, @filter, &1)}
      />

      <.empty_state :if={@any? and @total == 0} title="No visits match these filters.">
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
      <.recording_list
        live
        visits={@live}
        now={@now}
        path={&visit_path(@context, &1)}
        filter_path={&index_path(@context, Map.put(@filter, &1, &2), 1)}
      />
      <.recording_list
        visits={@saved}
        now={@now}
        path={&visit_path(@context, &1)}
        filter_path={&index_path(@context, Map.put(@filter, &1, &2), 1)}
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
