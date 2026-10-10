defmodule PhoenixReplay.Web.Components.Player.Playback do
  @moduledoc """
  The playback controls and the timeline, and the sheet listing the
  keyboard shortcuts, from `PhoenixReplay.Web.Player.Shortcuts`. They send
  `seek` with an `index` and optionally the time `at`, `previous`, `next`,
  `toggle`, `speed` with a `value`, `shortcuts` and `close_shortcuts`.

  Like the rest of the player's components, it takes the recording, the
  current position and URLs built by the player, never the socket.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]

  import PhoenixReplay.Web.Components.Core, only: [icon_button: 1, segmented: 1]
  import PhoenixReplay.Web.Components.Dialog, only: [dialog: 1]
  import PhoenixReplay.Web.Components.Keys, only: [kbd: 1]

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Web.Format
  alias PhoenixReplay.Web.Player.{Events, Shortcuts}

  @doc """
  Playback controls and the timeline: a lane of markers per kind of event
  and a playhead. The Scrubber hook maps the pointer to events and moves
  the playhead between them while playing.
  """
  attr :id, :string, required: true
  attr :recording, Recording, required: true
  attr :index, :integer, required: true
  attr :at, :integer, required: true
  attr :next_at, :integer, required: true
  attr :duration_ms, :integer, required: true
  attr :playing, :boolean, required: true
  attr :speed, :integer, required: true
  attr :speeds, :list, required: true
  attr :first, :integer, default: 0, doc: "the first event the view can be shown at"
  attr :slow_ms, :integer, default: 100, doc: "how long a collected event takes to count as slow"

  attr :visit, :map,
    default: nil,
    doc: """
    for a visit of several pages, the timeline runs on the visit's clock:
    `%{pages: Pages.t(), current: id, clock: %{at, until, playing?}}`; see
    `PhoenixReplay.Web.Player.Pages`
    """

  slot :visit_status, doc: "where playback stands in the visit, next to the clock"

  @spec playback(map()) :: Phoenix.LiveView.Rendered.t()
  def playback(%{visit: %{pages: pages, current: current, clock: clock}} = assigns) do
    %{offset: offset} = Enum.find(pages.pages, &(&1.id == current))

    assigns
    |> assign(
      lanes: pages.events,
      last: length(assigns.recording.events) - 1,
      clock_at: clock.at,
      clock_until: clock.until,
      clock_duration: pages.duration_ms,
      page_offset: offset,
      pages: pages,
      current: current
    )
    |> render_playback()
  end

  def playback(assigns) do
    lanes =
      for {kind, events} <- Events.lanes(assigns.recording),
          do: {kind, Enum.map(events, fn {event, _index} -> {event, nil} end)}

    assigns
    |> assign(
      lanes: lanes,
      last: length(assigns.recording.events) - 1,
      clock_at: assigns.at,
      clock_until: assigns.next_at,
      clock_duration: assigns.duration_ms,
      page_offset: 0,
      pages: nil,
      current: nil
    )
    |> render_playback()
  end

  defp render_playback(assigns) do
    ~H"""
    <section
      id={@id}
      aria-label="Playback"
      class="flex flex-col gap-3 rounded-xl border border-line bg-surface px-4 py-3"
    >
      <div class="flex flex-wrap items-center gap-2.5">
        <.icon_button
          phx-click="toggle"
          label={if @playing, do: "Pause", else: "Play"}
          variant="primary"
          size="lg"
          keys={Shortcuts.keys(:toggle)}
        >
          <.icon :if={@playing} name="lucide:pause" class="size-5" />
          <.icon :if={!@playing} name="lucide:play" class="size-5" />
        </.icon_button>
        <.icon_button
          phx-click="previous"
          label="Previous event"
          variant="ghost"
          keys={Shortcuts.keys(:previous)}
          disabled={@index <= @first}
        >
          <.icon name="lucide:chevron-left" class="size-4" />
        </.icon_button>
        <.icon_button
          phx-click="next"
          label="Next event"
          variant="ghost"
          keys={Shortcuts.keys(:next)}
          disabled={@index == @last}
        >
          <.icon name="lucide:chevron-right" class="size-4" />
        </.icon_button>
        <span class="ml-1 font-mono tabular-nums">
          {Format.precise_clock(@clock_at)}
          <span class="text-muted">/ {Format.precise_clock(@clock_duration)}</span>
        </span>
        {render_slot(@visit_status)}
        <span class="flex-1"></span>
        <.segmented
          label="Playback speed"
          options={for speed <- @speeds, do: {Integer.to_string(speed), "#{speed}×"}}
          value={Integer.to_string(@speed)}
          event="speed"
          keys={Shortcuts.speed_keys(@speeds)}
        />
        <.icon_button
          id="replay-shortcuts-button"
          phx-click="shortcuts"
          label="Keyboard shortcuts"
          variant="ghost"
          keys={Shortcuts.keys(:help)}
        >
          <.icon name="lucide:keyboard" class="size-4" />
        </.icon_button>
      </div>

      <div class="grid grid-cols-[4rem_minmax(0,1fr)] gap-x-3">
        <div class="flex flex-col gap-1 text-[11px] text-muted" aria-hidden="true">
          <span :if={@pages} class="flex items-center" style={"height: #{pages_height(@pages)}"}>
            Pages
          </span>
          <span :for={{kind, _events} <- @lanes} class="flex h-3.5 items-center">
            {Events.kind_label(kind)}
          </span>
        </div>
        <div
          id="replay-scrubber"
          phx-hook="Scrubber"
          role="slider"
          aria-label={if @pages, do: "Visit position", else: "Playback position"}
          aria-valuemin={@first}
          aria-valuemax={@last}
          aria-valuenow={@index}
          aria-valuetext={Format.clock(@clock_at)}
          tabindex="0"
          data-offsets={JSON.encode!(Enum.map(@recording.events, & &1.at))}
          data-at={@clock_at}
          data-next-at={@clock_until}
          data-duration={@clock_duration}
          data-mode={if @pages, do: "visit", else: "page"}
          data-page-offset={@page_offset}
          data-speed={@speed}
          data-playing={to_string(@playing)}
          class="relative flex cursor-pointer touch-none flex-col gap-1 rounded select-none"
        >
          <%!-- A visit's pages on its clock, the playing one in the accent colour. --%>
          <div :if={@pages} class="relative" style={"height: #{pages_height(@pages)}"}>
            <span
              :for={page <- @pages.pages}
              id={"replay-page-#{page.id}"}
              aria-current={page.id == @current && "page"}
              title={page_title(page)}
              class={[
                "absolute h-1.5 min-w-1 rounded-full",
                if(page.id == @current, do: "bg-accent", else: "bg-faint/50")
              ]}
              style={page_segment(page, @clock_duration)}
            ></span>
          </div>
          <div :for={{_kind, events} <- @lanes} class="relative h-3.5 rounded bg-track">
            <span
              :for={{event, page} <- events}
              class={[
                "absolute top-1/2 -translate-x-1/2 -translate-y-1/2 rounded-full",
                Events.marker_class(event, @slow_ms),
                page && page != @current && "opacity-35"
              ]}
              style={"left: #{position(event.at, @clock_duration)}%"}
              title={Events.marker_title(event)}
            ></span>
          </div>
          <span
            data-thumb
            aria-hidden="true"
            class="absolute -inset-y-0.5 w-0.5 -translate-x-1/2 rounded-full bg-ink"
            style={"left: #{position(@clock_at, @clock_duration)}%"}
          ></span>
        </div>
      </div>
    </section>
    """
  end

  # A row of page bars per lane the visit's pages take.
  defp pages_height(pages), do: "#{pages.lanes * 0.5 + 0.25}rem"

  defp page_segment(page, duration) do
    width = Float.round((page.end_at - page.offset) / max(duration, 1) * 100, 3)

    "left: #{position(page.offset, duration)}%; width: #{width}%; top: #{page.lane * 0.5 + 0.125}rem"
  end

  defp page_title(page) do
    path =
      if page.url,
        do: page.url |> Format.path_of() |> String.split("?", parts: 2) |> hd(),
        else: "—"

    "#{path} · at #{Format.clock(page.offset)}, #{Format.clock(page.end_at - page.offset)}"
  end

  defp position(_at, 0), do: 0
  defp position(at, duration_ms), do: Float.round(at / duration_ms * 100, 3)

  @doc """
  Every keyboard shortcut of the player, by group, from
  `PhoenixReplay.Web.Player.Shortcuts`. Escape or a click outside sends
  `"close_shortcuts"`.
  """
  @spec shortcut_sheet(map()) :: Phoenix.LiveView.Rendered.t()
  def shortcut_sheet(assigns) do
    assigns = assign(assigns, :groups, Shortcuts.groups())

    ~H"""
    <.dialog id="replay-shortcuts" title="Keyboard shortcuts" close="close_shortcuts" size="lg">
      <%!-- Groups flow into two columns where there is room, so the sheet fits. --%>
      <div class="gap-8 sm:columns-2">
        <section :for={{heading, shortcuts} <- @groups} class="mb-4 break-inside-avoid">
          <h3 class="mb-1 text-xs font-medium tracking-wide text-muted uppercase">{heading}</h3>
          <dl>
            <div :for={shortcut <- shortcuts} class="flex items-center justify-between gap-4 py-1">
              <dt>{shortcut.label}</dt>
              <dd class="flex shrink-0 items-center gap-1 text-xs text-muted">
                <%= for {combination, index} <- Enum.with_index(shortcut.keys) do %>
                  <span :if={index > 0}>or</span>
                  <.kbd keys={combination} />
                <% end %>
              </dd>
            </div>
          </dl>
        </section>
      </div>
    </.dialog>
    """
  end
end
