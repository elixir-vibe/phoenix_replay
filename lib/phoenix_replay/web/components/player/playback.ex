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
  alias PhoenixReplay.Recording.Event
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

  @spec playback(map()) :: Phoenix.LiveView.Rendered.t()
  def playback(assigns) do
    assigns =
      assign(assigns,
        lanes: Events.lanes(assigns.recording),
        last: length(assigns.recording.events) - 1
      )

    ~H"""
    <section
      id={@id}
      aria-label="Playback"
      class="flex flex-col gap-4 rounded-xl border border-line bg-surface px-4 py-3.5"
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
          size="lg"
          keys={Shortcuts.keys(:previous)}
          disabled={@index == 0}
        >
          <.icon name="lucide:chevron-left" class="size-4" />
        </.icon_button>
        <.icon_button
          phx-click="next"
          label="Next event"
          size="lg"
          keys={Shortcuts.keys(:next)}
          disabled={@index == @last}
        >
          <.icon name="lucide:chevron-right" class="size-4" />
        </.icon_button>
        <span class="ml-1.5 font-mono tabular-nums">
          {Format.precise_clock(@at)}
          <span class="text-muted">/ {Format.precise_clock(@duration_ms)}</span>
        </span>
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

      <div class="grid grid-cols-[4.5rem_minmax(0,1fr)] gap-x-3">
        <div class="flex flex-col gap-1.5 text-xs text-muted" aria-hidden="true">
          <span :for={{kind, _events} <- @lanes} class="flex h-[18px] items-center">
            {Events.kind_label(kind)}
          </span>
        </div>
        <div
          id="replay-scrubber"
          phx-hook="Scrubber"
          role="slider"
          aria-label="Playback position"
          aria-valuemin="0"
          aria-valuemax={@last}
          aria-valuenow={@index}
          aria-valuetext={Format.clock(@at)}
          tabindex="0"
          data-offsets={JSON.encode!(Enum.map(@recording.events, & &1.at))}
          data-at={@at}
          data-next-at={@next_at}
          data-duration={@duration_ms}
          data-speed={@speed}
          data-playing={to_string(@playing)}
          class="relative flex cursor-pointer touch-none flex-col gap-1.5 rounded select-none"
        >
          <div :for={{_kind, events} <- @lanes} class="relative h-[18px] rounded bg-track">
            <span
              :for={{event, _index} <- events}
              class={[
                "absolute top-1/2 -translate-x-1/2 -translate-y-1/2 rounded-full",
                Events.marker_class(event)
              ]}
              style={"left: #{position(event.at, @duration_ms)}%"}
              title={Event.label(event)}
            ></span>
          </div>
          <span
            data-thumb
            aria-hidden="true"
            class="absolute -top-1 -bottom-1 w-0.5 -translate-x-1/2 rounded-full bg-ink"
            style={"left: #{position(@at, @duration_ms)}%"}
          ></span>
        </div>
      </div>
    </section>
    """
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
