defmodule PhoenixReplay.Web.Components.Filters do
  @moduledoc """
  The recording list's filter bar: the search, when sessions started, the
  errors toggle, and chips for the fields of
  `PhoenixReplay.Web.FilterFields`, with the pickers that set them. They
  take a `PhoenixReplay.Recording.Filter` and a function from a filter to
  the list's URL, never the socket.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.Core, only: [close_menu: 2, local_time: 1, menu: 1]
  import PhoenixReplay.Web.Components.Keys, only: [kbd: 1]

  alias Phoenix.LiveView.JS
  alias PhoenixReplay.Recording.Filter
  alias PhoenixReplay.Web.{FilterFields, Format}

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
          <span class="sr-only">Search by URL, id or event</span>
          <input
            type="search"
            name="q"
            value={@filter.query}
            placeholder="Search URL, id or event"
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
      <span
        :for={{field, {prefix, shown}} <- @set}
        id={"recording-filter-chip-#{field.key}"}
        data-filter={field.key}
        class={chip_class()}
      >
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
  window, which links to the list filtered by it, or a range of days on a
  [Cally](https://wicky.nillia.ms/cally/) calendar with the times they
  start and end. The `TimeRange` hook reads the range in the viewer's time
  zone and sends it as `time_range` with `from` and `to` in UTC. Escape or a
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
      aria-label="When visits started"
      phx-click-away="close_filter"
      phx-window-keydown="close_filter"
      phx-key="Escape"
      phx-hook="Floating"
      data-anchor="recording-filter-time"
      data-placement="bottom-start"
      class="fixed top-0 left-0 z-40 flex w-[min(46rem,calc(100vw-1rem))] flex-col gap-1.5 rounded-lg border border-line bg-surface p-1.5 shadow-lg sm:flex-row"
    >
      <ul aria-label="Recent" class="shrink-0 sm:w-40">
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
        class="min-w-0 flex-1 border-t border-line px-2.5 pt-3 pb-1 sm:border-t-0 sm:border-l sm:pt-1"
      >
        <%!-- Cally draws the months; LiveView leaves them to it. --%>
        <div id="recording-filter-calendar" phx-update="ignore" data-calendar>
          <calendar-range months="2" page-by="single" class="block">
            <span slot="previous" aria-label="Previous month">
              <.icon name="lucide:chevron-left" class="size-4" />
            </span>
            <span slot="next" aria-label="Next month">
              <.icon name="lucide:chevron-right" class="size-4" />
            </span>
            <div class="flex justify-center gap-6">
              <calendar-month></calendar-month>
              <calendar-month offset="1" class="hidden sm:block"></calendar-month>
            </div>
          </calendar-range>
        </div>
        <div class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2">
          <label class="flex items-center gap-2">
            <span class="text-muted">From</span>
            <input type="time" name="from_time" value="00:00" class={time_input()} />
          </label>
          <label class="flex items-center gap-2">
            <span class="text-muted">to</span>
            <input type="time" name="to_time" value="23:59" class={time_input()} />
          </label>
          <span class="flex-1"></span>
          <button
            type="submit"
            class="h-9 rounded-md bg-ink px-3 font-medium text-on-ink hover:bg-ink/85"
          >
            Show this range
          </button>
        </div>
        <p class="mt-2 text-xs text-muted">
          Pick a day, or a first and a last day. In your time zone<span
            id="recording-filter-zone"
            phx-update="ignore"
            data-time-zone
          ></span>.
        </p>
      </form>
    </div>
    """
  end

  defp time_input,
    do: "h-9 rounded-md border border-line bg-canvas px-2 tabular-nums [color-scheme:inherit]"

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
      phx-hook="Floating"
      data-anchor={
        if Map.fetch!(@filter, @field.key),
          do: "recording-filter-chip-#{@field.key}",
          else: "recording-filter-add-button"
      }
      data-placement="bottom-start"
      class="fixed top-0 left-0 z-40 w-[min(24rem,calc(100vw-1rem))] rounded-lg border border-line bg-surface p-1.5 shadow-lg"
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
        No visits here have one{if @typed != "", do: " like that"}.
        <span :if={@typed != ""}>Press Enter to filter by it anyway.</span>
      </p>
    </div>
    """
  end
end
