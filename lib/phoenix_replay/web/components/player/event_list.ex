defmodule PhoenixReplay.Web.Components.Player.EventList do
  @moduledoc """
  The **Events** tab: the recording's events grouped by interaction, with
  a search, kind filters and a pane with the details of one event. It
  sends `seek` with an `index`, `toggle_kind` with a `kind`,
  `errors_only`, `search_events` with `q` and `pin_details`.

  Like the rest of the player's components, it takes the recording, the
  current position and URLs built by the player, never the socket.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]

  import PhoenixReplay.Web.Components.Core, only: [chip: 1]
  import PhoenixReplay.Web.Components.Layout, only: [data_list: 1]
  import PhoenixReplay.Web.Components.Keys, only: [aria_keyshortcuts: 1, kbd: 1]

  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Web.Format
  alias PhoenixReplay.Web.Player.{Events, Shortcuts}

  @doc "The icon for an event's type, or for a mark."
  attr :type, :atom,
    required: true,
    doc: "a `PhoenixReplay.Recording.Event` type, or `:mark` for a mark"

  attr :class, :any, default: "size-3.5"

  @spec event_icon(map()) :: Phoenix.LiveView.Rendered.t()
  def event_icon(assigns) do
    ~H"""
    <%= case @type do %>
      <% :mount -> %>
        <.icon name="lucide:rocket" class={@class} />
      <% :event -> %>
        <.icon name="lucide:mouse-pointer-click" class={@class} />
      <% :params -> %>
        <.icon name="lucide:link" class={@class} />
      <% :info -> %>
        <.icon name="lucide:mail" class={@class} />
      <% :render -> %>
        <.icon name="lucide:pencil-line" class={@class} />
      <% type when type in [:component, :component_destroyed] -> %>
        <.icon name="lucide:puzzle" class={@class} />
      <% :telemetry -> %>
        <.icon name="lucide:activity" class={@class} />
      <% :log -> %>
        <.icon name="lucide:message-square-text" class={@class} />
      <% :exit -> %>
        <.icon name="lucide:octagon-x" class={@class} />
      <% :viewport -> %>
        <.icon name="lucide:scaling" class={@class} />
      <% :state -> %>
        <.icon name="lucide:text-cursor-input" class={@class} />
      <% :mark -> %>
        <.icon name="lucide:flag" class={@class} />
    <% end %>
    """
  end

  @doc """
  The recording's events grouped by interaction, with a search, kind
  filters and, when there are errors, a filter to them alone, above a
  pane with the details of the current event, or of the one pinned there.

  Rows are one line each, so playback moves the highlight and nothing
  else; the pane changes its content but not its size. The divider
  between them resizes the pane, kept per browser by the
  `DetailsResizer` hook.
  """
  attr :groups, :list,
    required: true,
    doc: "the interactions shown, from `PhoenixReplay.Web.Player.Events.visible/2`"

  attr :kinds, :list, required: true
  attr :counts, :map, required: true, doc: "events of each kind"
  attr :error_count, :integer, required: true
  attr :index, :integer, required: true
  attr :hidden, :any, required: true, doc: "a `MapSet` of hidden kinds"
  attr :query, :string, default: ""
  attr :errors_only, :boolean, default: false

  attr :details, :any,
    default: nil,
    doc: "the `{event, index}` the pane describes: the current event or the pinned one"

  attr :pinned, :boolean, default: false
  attr :slow_ms, :integer, default: 100, doc: "how long a collected event takes to count as slow"

  @spec event_list(map()) :: Phoenix.LiveView.Rendered.t()
  def event_list(assigns) do
    assigns = assign(assigns, :search_keys, Shortcuts.keys(:search))

    ~H"""
    <div id="replay-events-panel" class="flex min-h-0 flex-1 flex-col [--details:14rem]">
      <div class="flex flex-col gap-2.5 border-b border-line p-3">
        <form id="replay-event-search" phx-change="search_events" phx-submit="search_events">
          <label class="flex h-9 items-center gap-2 rounded-lg border border-line bg-canvas px-2.5 focus-within:outline-2 focus-within:outline-accent">
            <.icon name="lucide:search" class="size-3.5 shrink-0 text-muted" />
            <span class="sr-only">Filter events</span>
            <input
              type="search"
              name="q"
              value={@query}
              placeholder="Filter events, SQL, logs"
              phx-debounce="200"
              data-shortcut="/"
              aria-keyshortcuts={aria_keyshortcuts(@search_keys)}
              class="peer h-full min-w-0 flex-1 bg-transparent text-[13px] outline-none placeholder:text-faint"
            />
            <.kbd
              keys={hd(@search_keys)}
              class="peer-focus:hidden peer-[:not(:placeholder-shown)]:hidden"
            />
          </label>
        </form>
        <div :if={length(@kinds) > 1 or @error_count > 0} class="flex flex-wrap gap-1.5">
          <.chip
            :for={kind <- @kinds}
            pressed={not MapSet.member?(@hidden, kind)}
            phx-click="toggle_kind"
            phx-value-kind={kind}
          >
            <span class={["size-2 rounded-sm", Events.kind_class(kind)]}></span>
            {Events.kind_label(kind)}
            <span class="text-muted">{@counts[kind]}</span>
          </.chip>
          <.chip
            :if={@error_count > 0}
            mode="only"
            tone="error"
            pressed={@errors_only}
            phx-click="errors_only"
          >
            <span class="size-2 rounded-sm bg-error"></span>
            Errors <span class="opacity-70">{@error_count}</span>
          </.chip>
        </div>
      </div>
      <ol
        id="replay-events"
        phx-hook="EventList"
        class="relative max-h-[calc(100dvh_-_14rem_-_var(--details))] min-h-32 flex-1 overflow-y-auto overscroll-contain py-1.5"
      >
        <li :if={@groups == []} class="px-4 py-8 text-center text-sm text-muted">
          No events match.
        </li>
        <li :for={{head, rows} <- @groups}>
          <.event_row event={head} current={@index} slow_ms={@slow_ms} head />
          <ol :if={rows != []} class="pb-1">
            <li :for={row <- rows}>
              <.event_row event={row} current={@index} slow_ms={@slow_ms} />
            </li>
          </ol>
        </li>
      </ol>
      <div
        :if={@details}
        id="replay-details-resizer"
        phx-hook="DetailsResizer"
        data-container="replay-events-panel"
        role="separator"
        aria-orientation="horizontal"
        aria-label="Resize the event details"
        aria-controls="replay-details"
        tabindex="0"
        class="h-1.5 shrink-0 cursor-row-resize touch-none border-t border-line transition-colors hover:bg-accent/30 focus-visible:bg-accent/30"
      >
      </div>
      <.event_details :if={@details} event={@details} pinned={@pinned} />
    </div>
    """
  end

  attr :event, :any, required: true, doc: "an `{event, index}` pair"
  attr :pinned, :boolean, required: true

  defp event_details(%{event: {event, index}} = assigns) do
    assigns = assign(assigns, ev: event, index: index, details: Events.details(event))

    ~H"""
    <section
      id="replay-details"
      aria-label="Event details"
      data-index={@index}
      class="h-(--details) shrink-0 overflow-y-auto overscroll-contain bg-canvas"
    >
      <header class="sticky top-0 flex items-center gap-2 border-b border-line bg-canvas/95 px-3.5 py-2 text-[13px] backdrop-blur">
        <.event_icon type={icon_type(@ev)} class="size-3.5 shrink-0 opacity-70" />
        <span class="min-w-0 flex-1 truncate font-medium" title={Event.label(@ev)}>
          <%= for {kind, content} <- Events.parts(@ev) do %>
            <span :if={kind == :text}>{content}</span>
            <code :if={kind == :code} class="font-mono text-xs font-normal">{content}</code>
          <% end %>
        </span>
        <span class="shrink-0 font-mono text-[11px] tabular-nums text-muted">
          {Format.clock(@ev.at)}
        </span>
        <button
          id="replay-details-pin"
          type="button"
          phx-click="pin_details"
          aria-pressed={to_string(@pinned)}
          aria-label={if @pinned, do: "Follow playback", else: "Pin these details"}
          title={
            if @pinned,
              do: "Pinned: playback goes on without changing these details",
              else: "Pin these details while playback goes on"
          }
          class="inline-flex size-6 shrink-0 items-center justify-center rounded-md text-muted transition-colors hover:bg-hover hover:text-ink aria-pressed:bg-accent/15 aria-pressed:text-accent"
        >
          <.icon name="lucide:pin" class="size-3.5" />
        </button>
      </header>
      <.data_list :if={@details != []} class="px-3.5 py-3">
        <:item :for={{name, value} <- @details} title={name}>{value}</:item>
      </.data_list>
    </section>
    """
  end

  attr :event, :any, required: true, doc: "an `{event, index}` pair"
  attr :current, :integer, required: true
  attr :slow_ms, :integer, required: true
  attr :head, :boolean, default: false

  defp event_row(%{event: {event, index}} = assigns) do
    assigns =
      assign(assigns,
        ev: event,
        index: index,
        parts: Events.parts(event),
        mark: Event.mark_name(event),
        slow?: Events.slow?(event, assigns.slow_ms)
      )

    ~H"""
    <button
      type="button"
      phx-click="seek"
      phx-value-index={@index}
      aria-current={@index == @current && "step"}
      class={[
        "flex w-full min-w-0 items-center gap-2.5 py-1.5 pr-3.5 text-left transition-colors pointer-coarse:py-2.5",
        @head && "pl-3.5 text-sm font-medium",
        !@head && "pl-9 text-[13px]",
        @index == @current && "bg-accent-soft",
        @index != @current && "hover:bg-hover",
        @index > @current && "text-faint",
        @index <= @current && Event.error?(@ev) && "text-error"
      ]}
    >
      <.event_icon type={icon_type(@ev)} class="size-3.5 shrink-0 opacity-70" />
      <span class="min-w-0 flex-1 truncate" title={Events.marker_title(@ev)}>
        <span
          :if={@mark}
          class="mr-1 rounded-full bg-kind-mark/15 px-1.5 py-px text-[11px] font-medium text-kind-mark"
        >
          {@mark}
        </span>
        <%= for {kind, content} <- @parts do %>
          <span :if={kind == :text}>{content}</span>
          <code :if={kind == :code} class="font-mono text-xs">{content}</code>
        <% end %>
      </span>
      <span
        :if={duration = Event.duration(@ev)}
        title={@slow? && "Slower than #{Format.milliseconds(@slow_ms)}"}
        class={[
          "shrink-0 font-mono text-[11px] tabular-nums",
          @slow? && "font-medium text-slow",
          !@slow? && "text-muted"
        ]}
      >
        {Format.milliseconds(duration)}
      </span>
      <span class="shrink-0 font-mono text-[11px] tabular-nums text-muted">
        {Format.clock(@ev.at)}
      </span>
    </button>
    """
  end

  defp icon_type(event), do: if(Event.mark?(event), do: :mark, else: event.type)
end
