defmodule PhoenixReplay.Web.Components.Recordings do
  @moduledoc """
  Components of the recording list. They take
  `PhoenixReplay.Recording.Summary` structs and functions that build URLs,
  never the socket.

  Each row is a single link stretched over the whole row, so the row opens
  the recording; its delete button sits above the link.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.Core, only: [badge: 1]

  alias PhoenixReplay.Recording.Summary
  alias PhoenixReplay.Recordings.Filter
  alias PhoenixReplay.Web.Format

  # Columns on wider screens: mark, session, started, duration, events,
  # status, action. Phones show the mark, the session and the status.
  @columns "grid-cols-[1rem_minmax(0,1fr)_auto] sm:grid-cols-[1rem_minmax(0,1fr)_8rem_4.5rem_4.5rem_6.5rem_2rem]"

  @doc """
  A section of recordings: sessions still recording with `live`, or saved
  ones under a header row. `delete` names the event that deletes a saved
  recording, or is `nil` when the viewer may not delete.
  """
  attr :recordings, :list, required: true
  attr :now, :integer, required: true
  attr :path, :any, required: true, doc: "a function from a summary to its URL"
  attr :live, :boolean, default: false
  attr :delete, :string, default: nil

  @spec recording_list(map()) :: Phoenix.LiveView.Rendered.t()
  def recording_list(%{live: true} = assigns) do
    ~H"""
    <section :if={@recordings != []} aria-labelledby="recordings-live" class="mb-6">
      <h2
        id="recordings-live"
        class="mb-2 flex items-center gap-2 text-xs font-medium tracking-wide text-muted uppercase"
      >
        <span class="size-2 animate-pulse rounded-full bg-live"></span> Live now
      </h2>
      <ul class="divide-y divide-line overflow-hidden rounded-xl border border-line bg-surface">
        <.row :for={recording <- @recordings} recording={recording} path={@path.(recording)}>
          <:mark><span class="size-2.5 animate-pulse rounded-full bg-live"></span></:mark>
          <:meta>
            Live · {Format.clock(recording.duration_ms)} · {Format.count(
              recording.event_count,
              "event"
            )}
          </:meta>
          <:started>Started {Format.relative(recording.connected_at, @now)}</:started>
          <:status><span class="font-medium text-live">Recording</span></:status>
          <:action>
            <.icon name="lucide:chevron-right" class="size-4 text-muted" />
          </:action>
        </.row>
      </ul>
    </section>
    """
  end

  def recording_list(assigns) do
    assigns = assign(assigns, :columns, @columns)

    ~H"""
    <section :if={@recordings != []} aria-labelledby="recordings-saved">
      <h2 id="recordings-saved" class="mb-2 text-xs font-medium tracking-wide text-muted uppercase">
        Saved
      </h2>
      <div class="overflow-hidden rounded-xl border border-line bg-surface">
        <div
          aria-hidden="true"
          class={[
            "hidden gap-x-4 border-b border-line px-4 py-2.5 text-xs text-muted sm:grid",
            @columns
          ]}
        >
          <span></span><span>Session</span><span>Started</span><span>Duration</span>
          <span>Events</span><span>Errors</span><span></span>
        </div>
        <ul class="divide-y divide-line">
          <.row :for={recording <- @recordings} recording={recording} path={@path.(recording)}>
            <:mark><.icon name="lucide:circle-play" class="size-4 text-muted" /></:mark>
            <:meta>
              {Format.relative(recording.connected_at, @now)} · {Format.count(
                recording.event_count,
                "event"
              )}
            </:meta>
            <:started>
              <span title={Format.timestamp(recording.connected_at) <> " UTC"}>
                {Format.relative(recording.connected_at, @now)}
              </span>
            </:started>
            <:status>
              <.badge :if={recording.error_count > 0} tone="error" dot="static">
                {Format.count(recording.error_count, "error")}
              </.badge>
              <span :if={recording.error_count == 0} class="hidden text-muted sm:inline">None</span>
            </:status>
            <:action>
              <button
                :if={@delete}
                type="button"
                phx-click={@delete}
                phx-value-id={recording.id}
                data-confirm="Delete this recording?"
                aria-label={"Delete recording #{short_id(recording)}"}
                title="Delete recording"
                class="relative z-10 inline-flex size-8 items-center justify-center rounded-md text-muted opacity-0 transition group-hover:opacity-100 hover:bg-error-soft hover:text-error focus-visible:opacity-100 pointer-coarse:opacity-100"
              >
                <.icon name="lucide:trash-2" class="size-4" />
              </button>
            </:action>
          </.row>
        </ul>
      </div>
    </section>
    """
  end

  @doc """
  Says how many recordings ended since the list was read, with a button
  that sends `show_new` to bring it up to date.
  """
  attr :count, :integer, required: true

  @spec new_recordings(map()) :: Phoenix.LiveView.Rendered.t()
  def new_recordings(assigns) do
    ~H"""
    <div id="recordings-new" role="status" aria-live="polite">
      <button
        :if={@count > 0}
        type="button"
        phx-click="show_new"
        class="mb-4 flex w-full items-center justify-center gap-2 rounded-xl border border-accent/30 bg-accent-soft px-4 py-2.5 text-sm font-medium text-ink transition-colors hover:border-accent/60 pointer-coarse:py-3"
      >
        <.icon name="lucide:arrow-up" class="size-4 text-accent" />
        {Format.count(@count, "new recording")} · Show
      </button>
    </div>
    """
  end

  @doc """
  Narrows the list. Changes are sent as `filter` with the fields of
  `PhoenixReplay.Recordings.Filter.from_params/1`.
  """
  attr :filter, Filter, required: true
  attr :views, :list, required: true
  attr :event_names, :list, required: true

  @spec filter_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def filter_bar(assigns) do
    assigns =
      assign(assigns,
        field:
          "flex h-10 items-center gap-1.5 rounded-lg border border-line bg-surface px-3 focus-within:outline-2 focus-within:outline-accent pointer-coarse:h-11",
        select: "cursor-pointer bg-transparent font-medium outline-none"
      )

    ~H"""
    <form
      id="recording-filter"
      role="search"
      phx-change="filter"
      phx-submit="filter"
      class="mb-6 flex flex-wrap items-center gap-2 text-sm"
    >
      <label class={[@field, "min-w-0 flex-[1_1_14rem]"]}>
        <.icon name="lucide:search" class="size-4 shrink-0 text-muted" />
        <span class="sr-only">Search by URL or id</span>
        <input
          type="search"
          name="q"
          value={@filter.query}
          placeholder="Search URL or session id"
          phx-debounce="300"
          class="h-full min-w-0 flex-1 bg-transparent outline-none placeholder:text-faint"
        />
      </label>
      <label class={@field}>
        <span class="text-muted">View</span>
        <select name="view" class={[@select, "max-w-44 truncate"]}>
          <option value="">All</option>
          <option :for={view <- @views} value={view} selected={view == @filter.view}>{view}</option>
        </select>
      </label>
      <label class={@field}>
        <span class="text-muted">Started</span>
        <select name="within" class={@select}>
          <option value="">Any time</option>
          <option :for={window <- Filter.windows()} value={window} selected={window == @filter.within}>
            Last {window}
          </option>
        </select>
      </label>
      <label class={@field}>
        <span class="text-muted">Event</span>
        <input
          type="text"
          name="event"
          value={@filter.event}
          list="recording-filter-events"
          placeholder="Any"
          phx-debounce="300"
          class="w-24 bg-transparent font-medium outline-none placeholder:text-ink"
        />
        <datalist id="recording-filter-events">
          <option :for={name <- @event_names} value={name} />
        </datalist>
      </label>
      <label class={@field}>
        <span class="text-muted">Min events</span>
        <input
          type="number"
          name="min_events"
          min="1"
          value={@filter.min_events}
          placeholder="Any"
          phx-debounce="300"
          class="w-14 bg-transparent font-medium outline-none placeholder:text-ink"
        />
      </label>
      <label class={[
        @field,
        "cursor-pointer font-medium has-checked:border-error has-checked:bg-error-soft has-checked:text-error"
      ]}>
        <input type="checkbox" name="errors" value="1" checked={@filter.errors} class="sr-only" />
        <.icon name="lucide:triangle-alert" class="size-4" /> With errors
      </label>
    </form>
    """
  end

  attr :recording, Summary, required: true
  attr :path, :string, required: true
  slot :mark, required: true
  slot :meta, required: true, doc: "the second line on phones"
  slot :started, required: true
  slot :status, required: true
  slot :action, required: true

  defp row(assigns) do
    assigns = assign(assigns, :columns, @columns)

    ~H"""
    <li
      id={"recording-#{@recording.id}"}
      class={[
        "group relative grid items-center gap-x-4 px-4 py-3 transition-colors hover:bg-hover",
        @columns
      ]}
    >
      <span class="flex justify-center">{render_slot(@mark)}</span>
      <div class="min-w-0">
        <.link
          navigate={@path}
          class="block truncate font-medium after:absolute after:inset-0 focus-visible:outline-none after:focus-visible:outline-2 after:focus-visible:-outline-offset-2 after:focus-visible:outline-accent"
        >
          {@recording.view}
        </.link>
        <p class="mt-0.5 truncate font-mono text-xs text-muted">
          <span class="sm:hidden">{render_slot(@meta)}</span>
          <span class="hidden sm:inline">
            {page(@recording)} · {short_id(@recording)}
          </span>
        </p>
      </div>
      <span class="hidden text-sm text-muted sm:block">{render_slot(@started)}</span>
      <span class="hidden font-mono text-sm tabular-nums sm:block">
        {Format.clock(@recording.duration_ms)}
      </span>
      <span class="hidden text-sm text-muted tabular-nums sm:block">{@recording.event_count}</span>
      <span class="justify-self-end text-sm sm:justify-self-start">{render_slot(@status)}</span>
      <span class="hidden justify-center sm:flex">{render_slot(@action)}</span>
    </li>
    """
  end

  defp page(%Summary{url: nil}), do: "—"
  defp page(%Summary{url: url}), do: Format.path_of(url)

  defp short_id(%Summary{id: id}), do: String.slice(id, 0, 8)
end
