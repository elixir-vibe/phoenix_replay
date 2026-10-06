defmodule PhoenixReplay.Web.Components.RecordingList do
  @moduledoc """
  Components of the recording list. They take
  `PhoenixReplay.Recording.Summary` structs and functions that build URLs,
  never the socket.

  Each row is a single link stretched over the whole row, so the row opens
  the recording; its delete button sits above the link.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]

  import PhoenixReplay.Web.Components.Core,
    only: [badge: 1, close_menu: 2, kbd: 1, local_time: 1, menu: 1]

  alias Phoenix.LiveView.JS
  alias PhoenixReplay.Recording.{Client, Filter, Summary}
  alias PhoenixReplay.Web.{FilterFields, Format}

  # Columns on wider screens: mark, session, started, duration, events,
  # status, action. Phones show the mark, the session and the status.
  @columns "grid-cols-[1rem_minmax(0,1fr)_auto] sm:grid-cols-[1rem_minmax(0,1fr)_8rem_4.5rem_4.5rem_6.5rem_2rem]"

  @doc """
  A section of recordings: sessions still recording with `live`, or saved
  ones under a header row. `delete` names the event that deletes a saved
  recording, or is `nil` when the viewer may not delete. Where each visit
  came from links to the list filtered by it, through `filter_path`.
  """
  attr :recordings, :list, required: true
  attr :now, :integer, required: true
  attr :path, :any, required: true, doc: "a function from a summary to its URL"

  attr :filter_path, :any,
    required: true,
    doc: "a function from a criterion and its value to the list's URL filtered by it"

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
        <.row
          :for={recording <- @recordings}
          recording={recording}
          path={@path.(recording)}
          filter_path={@filter_path}
        >
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
    # Older starts read as dates, in the viewer's time zone.
    assigns = assign(assigns, columns: @columns, two_days: :timer.hours(48))

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
          <.row
            :for={recording <- @recordings}
            recording={recording}
            path={@path.(recording)}
            filter_path={@filter_path}
          >
            <:mark><.device_icon viewport={recording.viewport} /></:mark>
            <:meta>
              {Format.relative(recording.connected_at, @now)} · {Format.count(
                recording.event_count,
                "event"
              )}
            </:meta>
            <:started>
              <.local_time
                id={"recording-#{recording.id}-started"}
                at={recording.connected_at}
                format={if @now - recording.connected_at < @two_days, do: "title", else: "date"}
              >
                {Format.relative(recording.connected_at, @now)}
              </.local_time>
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
  Narrows the list. The search is sent as `filter` with `q`; the errors
  toggle, chips and values are links to the list filtered. **Started**
  sends `edit_time` to open `time_picker/1` as `editing: :time`.

  The other fields of `PhoenixReplay.Web.FilterFields` show as chips
  once set, and **+ Filter** adds one: it sends `edit_filter` with the
  `field`, as a chip does to change its value, and the list opens the
  value picker for `editing`, `filter_value/1`.
  """
  attr :filter, Filter, required: true
  attr :path, :any, required: true, doc: "a function from a filter to the list's URL"

  attr :editing, :any,
    default: nil,
    doc: "the field whose value is being chosen, or `:time` for when sessions started"

  attr :values, :list, default: [], doc: "the `editing` field's values, with counts"
  attr :typed, :string, default: "", doc: "what was typed in the value picker"

  @spec filter_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def filter_bar(assigns) do
    assigns =
      assign(assigns,
        field:
          "flex h-10 items-center gap-1.5 rounded-lg border border-line bg-surface px-3 focus-within:outline-2 focus-within:outline-accent pointer-coarse:h-11",
        set:
          for(
            {field, value} <- FilterFields.set(assigns.filter),
            do: {field, FilterFields.describe(field, value)}
          ),
        unset: FilterFields.unset(assigns.filter),
        errors_toggled: %Filter{assigns.filter | errors: not assigns.filter.errors},
        without_tab: %Filter{assigns.filter | tab: nil}
      )

    ~H"""
    <div id="recording-filter" class="relative mb-6 flex flex-wrap items-center gap-2 text-sm">
      <form
        id="recording-search"
        role="search"
        phx-change="filter"
        phx-submit="filter"
        class="contents"
      >
        <label class={[@field, "min-w-0 flex-[1_1_14rem]"]}>
          <.icon name="lucide:search" class="size-4 shrink-0 text-muted" />
          <span class="sr-only">Search by URL, session id or event</span>
          <input
            type="search"
            name="q"
            value={@filter.query}
            placeholder="Search URL, session id or event"
            phx-debounce="300"
            data-shortcut="/"
            class="h-full min-w-0 flex-1 bg-transparent outline-none placeholder:text-faint"
          />
          <.kbd keys={["/"]} class="hidden sm:inline-flex" />
        </label>
      </form>
      <button
        id="recording-filter-time"
        type="button"
        phx-click="edit_time"
        aria-haspopup="dialog"
        aria-expanded={to_string(@editing == :time)}
        class={[@field, "font-medium hover:bg-hover"]}
      >
        <.icon name="lucide:clock" class="size-4 text-muted" />
        <span class="text-muted">Started</span>
        <.time_label filter={@filter} />
        <.icon name="lucide:chevron-down" class="size-3.5 text-muted" />
      </button>
      <.link
        id="recording-filter-errors"
        patch={@path.(@errors_toggled)}
        aria-pressed={to_string(@filter.errors)}
        class={[
          @field,
          "font-medium",
          @filter.errors && "border-error bg-error-soft text-error",
          !@filter.errors && "hover:bg-hover"
        ]}
      >
        <.icon name="lucide:triangle-alert" class="size-4" /> With errors
      </.link>
      <span :for={{field, {prefix, shown}} <- @set} data-filter={field.key} class={chip_class()}>
        <button
          type="button"
          phx-click="edit_filter"
          phx-value-field={field.key}
          aria-label={"Change the filter #{prefix} #{shown}"}
          class="flex min-w-0 items-center gap-1 rounded-l-full py-1 pr-1 pl-3 hover:bg-hover"
        >
          <span class="text-muted">{prefix}</span>
          <span class="max-w-56 truncate font-medium">{shown}</span>
        </button>
        <.remove_filter path={@path.(FilterFields.without(@filter, field))} label={field.label} />
      </span>
      <span :if={@filter.tab} data-filter="tab" class={chip_class()}>
        <span class="py-1 pl-3 font-medium">This browser tab</span>
        <.remove_filter path={@path.(@without_tab)} label="browser tab" />
      </span>
      <.menu
        :if={@unset != []}
        id="recording-filter-add"
        label="Add a filter"
        trigger_class="inline-flex h-10 items-center gap-1.5 rounded-lg border border-dashed border-line px-3 font-medium text-muted transition-colors hover:bg-hover hover:text-ink aria-expanded:text-ink pointer-coarse:h-11"
      >
        <:trigger><.icon name="lucide:plus" class="size-4" /> Filter</:trigger>
        <:item :for={field <- @unset}>
          <button
            type="button"
            phx-click={
              JS.push("edit_filter", value: %{field: field.key}) |> close_menu("recording-filter-add")
            }
          >
            {field.label}
          </button>
        </:item>
      </.menu>
      <.time_picker :if={@editing == :time} filter={@filter} path={@path} />
      <.filter_value
        :if={is_map(@editing)}
        field={@editing}
        filter={@filter}
        values={@values}
        typed={@typed}
        path={@path}
      />
    </div>
    """
  end

  attr :filter, Filter, required: true

  # When the sessions shown started: a window, a range in the viewer's
  # time zone, or any time.
  defp time_label(assigns) do
    ~H"""
    <span :if={@filter.within}>{Format.window(@filter.within)}</span>
    <span :if={@filter.from || @filter.to} class="inline-flex items-center gap-1">
      <span :if={!@filter.from}>before</span>
      <.local_time :if={@filter.from} id="recording-filter-from" at={@filter.from}>
        {Format.started(@filter.from)} UTC
      </.local_time>
      <span :if={@filter.from && @filter.to}>–</span>
      <span :if={@filter.from && !@filter.to}>on</span>
      <.local_time :if={@filter.to} id="recording-filter-to" at={@filter.to}>
        {Format.started(@filter.to)} UTC
      </.local_time>
    </span>
    <span :if={!@filter.within && !@filter.from && !@filter.to}>Any time</span>
    """
  end

  @doc """
  Chooses when the sessions shown started, under the filter bar: a recent
  window, which links to the list filtered by it, or a range. The
  `TimeRange` hook reads the range in the viewer's time zone and sends it
  as `time_range` with `from` and `to` in UTC, either blank. Escape or a
  click outside sends `close_filter`.
  """
  attr :filter, Filter, required: true
  attr :path, :any, required: true

  @spec time_picker(map()) :: Phoenix.LiveView.Rendered.t()
  def time_picker(assigns) do
    assigns =
      assign(assigns,
        windows:
          for(
            window <- [nil | Filter.windows()],
            do: {window, %Filter{assigns.filter | within: window, from: nil, to: nil}}
          ),
        iso: &(&1 && &1 |> DateTime.from_unix!(:millisecond) |> DateTime.to_iso8601())
      )

    ~H"""
    <div
      id="recording-filter-time-picker"
      role="dialog"
      aria-label="When sessions started"
      phx-click-away="close_filter"
      phx-window-keydown="close_filter"
      phx-key="Escape"
      class="absolute top-full right-0 left-0 z-30 mt-1 rounded-lg border border-line bg-surface p-1.5 shadow-lg sm:left-auto sm:w-80"
    >
      <ul aria-label="Recent">
        <li :for={{window, filter} <- @windows}>
          <.link
            patch={@path.(filter)}
            aria-current={(window == @filter.within and !@filter.from and !@filter.to) && "true"}
            class="group flex items-center gap-2 rounded-md px-2.5 py-1.5 hover:bg-hover focus-visible:bg-hover"
          >
            <.icon
              name="lucide:check"
              class="size-3.5 shrink-0 opacity-0 group-aria-[current=true]:opacity-100"
            />
            {if window, do: Format.window(window), else: "Any time"}
          </.link>
        </li>
      </ul>
      <form
        id="recording-filter-range"
        phx-hook="TimeRange"
        data-from={@iso.(@filter.from)}
        data-to={@iso.(@filter.to)}
        class="mt-1.5 grid grid-cols-[auto_minmax(0,1fr)] items-center gap-x-3 gap-y-2 border-t border-line px-2.5 pt-3 pb-1"
      >
        <label for="recording-filter-range-from" class="text-muted">From</label>
        <input
          id="recording-filter-range-from"
          type="datetime-local"
          name="from"
          class="h-9 min-w-0 rounded-md border border-line bg-canvas px-2 [color-scheme:inherit]"
        />
        <label for="recording-filter-range-to" class="text-muted">To</label>
        <input
          id="recording-filter-range-to"
          type="datetime-local"
          name="to"
          class="h-9 min-w-0 rounded-md border border-line bg-canvas px-2 [color-scheme:inherit]"
        />
        <p class="col-span-2 text-xs text-muted">
          In your time zone<span id="recording-filter-zone" phx-update="ignore" data-time-zone></span>.
        </p>
        <button
          type="submit"
          class="col-span-2 h-9 rounded-md bg-ink font-medium text-on-ink hover:bg-ink/85"
        >
          Show this range
        </button>
      </form>
    </div>
    """
  end

  defp chip_class,
    do:
      "inline-flex h-10 max-w-full items-center rounded-full border border-line bg-surface pointer-coarse:h-11"

  attr :path, :string, required: true
  attr :label, :string, required: true

  defp remove_filter(assigns) do
    ~H"""
    <.link
      patch={@path}
      aria-label={"Remove the #{@label} filter"}
      class="flex h-full items-center rounded-r-full pr-2.5 pl-1 text-muted hover:bg-hover hover:text-ink"
    >
      <.icon name="lucide:x" class="size-3.5" />
    </.link>
    """
  end

  @doc """
  Asks for the value of a filter field, under the filter bar. A choice
  lists the values recordings have, the most common first, narrowed by
  what is typed, which `type_value` sends as `value`, with the one set
  now marked; a duration lists a few. Each links to the list filtered by
  it. Enter, or **Apply** for a number, sends `apply_filter` with the
  `value` typed. Escape or a click outside sends `close_filter`.
  """
  attr :field, :map, required: true
  attr :filter, Filter, required: true
  attr :values, :list, required: true
  attr :typed, :string, required: true
  attr :path, :any, required: true

  @spec filter_value(map()) :: Phoenix.LiveView.Rendered.t()
  def filter_value(assigns) do
    typed = String.downcase(String.trim(assigns.typed))

    %{field: field, filter: filter} = assigns
    current = Map.fetch!(filter, field.key)

    shown =
      case field.control do
        :choice ->
          for {value, count} <- assigns.values,
              String.contains?(String.downcase(FilterFields.display(field, value)), typed),
              do: {value, FilterFields.display(field, value), count}

        :duration ->
          for seconds <- FilterFields.durations(),
              do: {Integer.to_string(seconds), Format.seconds(seconds), nil}

        :number ->
          []
      end

    assigns =
      assign(assigns,
        current: current && to_string(current),
        prefix: if(field.control == :duration, do: "Longer than", else: field.label <> " is"),
        typed?: field.control != :choice,
        shown: shown
      )

    ~H"""
    <div
      id="recording-filter-value"
      role="dialog"
      aria-label={"Filter by #{@field.label}"}
      phx-click-away="close_filter"
      phx-window-keydown="close_filter"
      phx-key="Escape"
      class="absolute top-full right-0 left-0 z-30 mt-1 rounded-lg sm:left-auto sm:w-96 border border-line bg-surface p-1.5 shadow-lg"
    >
      <form
        id="recording-filter-value-form"
        phx-change="type_value"
        phx-submit="apply_filter"
        class="flex gap-1.5"
      >
        <label class="flex h-9 min-w-0 flex-1 items-center gap-2 rounded-md border border-line bg-canvas px-2.5 focus-within:outline-2 focus-within:outline-accent">
          <span class="shrink-0 text-muted">{@prefix}</span>
          <input
            type={if @typed?, do: "number", else: "text"}
            name="value"
            min={@typed? && "1"}
            value={@typed}
            placeholder={
              @current ||
                case @field.control do
                  :choice -> "Any value"
                  :duration -> "Seconds"
                  :number -> "1"
                end
            }
            autocomplete="off"
            phx-debounce={@field.control == :choice && "150"}
            phx-mounted={JS.focus()}
            class="h-full min-w-0 flex-1 bg-transparent font-medium outline-none"
          />
        </label>
        <span :if={@field.control == :duration} class="self-center text-muted">s</span>
        <button
          :if={@typed?}
          type="submit"
          class="h-9 rounded-md bg-ink px-3 font-medium text-on-ink hover:bg-ink/85"
        >
          Apply
        </button>
      </form>
      <ul
        :if={@shown != []}
        aria-label={"#{@field.label} values"}
        class="mt-1 max-h-72 overflow-y-auto"
      >
        <li :for={{value, label, count} <- @shown}>
          <.link
            patch={@path.(FilterFields.put(@filter, @field, value))}
            aria-current={value == @current && "true"}
            class="group flex items-center gap-2 rounded-md px-2.5 py-1.5 hover:bg-hover focus-visible:bg-hover"
          >
            <.icon
              name="lucide:check"
              class="size-3.5 shrink-0 opacity-0 group-aria-[current=true]:opacity-100"
            />
            <span class="min-w-0 flex-1 truncate">{label}</span>
            <span :if={count} class="text-muted tabular-nums">{count}</span>
          </.link>
        </li>
      </ul>
      <p :if={@field.control == :choice and @shown == []} class="px-2.5 py-2 text-muted">
        No recordings here have one{if @typed != "", do: " like that"}.
        <span :if={@typed != ""}>Press Enter to filter by it anyway.</span>
      </p>
    </div>
    """
  end

  attr :recording, Summary, required: true
  attr :path, :string, required: true
  attr :filter_path, :any, required: true
  slot :mark, required: true
  slot :meta, required: true, doc: "the second line on phones"
  slot :started, required: true
  slot :status, required: true
  slot :action, required: true

  defp row(assigns) do
    assigns = assign(assigns, columns: @columns, traffic: traffic_of(assigns.recording))

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
            {page(@recording)}<span :if={@recording.device}> · {@recording.device}</span><.traffic
              :if={@traffic != []}
              traffic={@traffic}
              filter_path={@filter_path}
            /> · {short_id(@recording)}
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

  attr :viewport, :map, default: nil

  # The kind of device the session ran on; see `Client.device_type/1`.
  defp device_icon(assigns) do
    ~H"""
    <%= case Client.device_type(@viewport) do %>
      <% nil -> %>
        <.icon name="lucide:circle-play" class="size-4 text-muted" />
      <% "phone" -> %>
        <.icon name="lucide:smartphone" class="size-4 text-muted" label="Phone" />
      <% "tablet" -> %>
        <.icon name="lucide:tablet" class="size-4 text-muted" label="Tablet" />
      <% "desktop" -> %>
        <.icon name="lucide:monitor" class="size-4 text-muted" label="Desktop" />
    <% end %>
    """
  end

  attr :traffic, :list, required: true
  attr :filter_path, :any, required: true

  # Each part of where the visit came from links to the list filtered by it.
  defp traffic(%{traffic: _traffic} = assigns) do
    ~H"""
    <span phx-no-format> · from <%= for {{criterion, value}, index} <- Enum.with_index(@traffic) do %><%= if index > 0 do %> / <% end %><.link patch={@filter_path.(criterion, value)} class="relative z-10 hover:text-ink hover:underline">{value}</.link><% end %></span>
    """
  end

  # Where the visit came from, leaving out what says nothing: a direct
  # visit, no medium, or a referral, which the referrer's host as the
  # source already tells.
  defp traffic_of(%Summary{source: source, medium: medium, campaign: campaign}) do
    [
      {:source, if(source != "(direct)", do: source)},
      {:medium, if(medium not in ["(none)", "referral"], do: medium)},
      {:campaign, campaign}
    ]
    |> Enum.reject(fn {_criterion, value} -> is_nil(value) end)
  end

  defp page(%Summary{url: nil}), do: "—"
  defp page(%Summary{url: url}), do: Format.path_of(url)

  defp short_id(%Summary{id: id}), do: String.slice(id, 0, 8)
end
