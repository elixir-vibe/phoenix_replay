defmodule PhoenixReplay.Web.Components.Player do
  @moduledoc """
  Components of the player that know about recordings and their events.

  They take the recording, the current position and URLs built by the
  player, never the socket. Events are sent by name: `seek` with an
  `index`, `previous`, `next`, `toggle`, `speed` and `frame_mode` with a
  `value`, `toggle_kind` with a `kind`, `errors_only`, and `search_events`
  with `q`.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]
  import PhoenixReplay.Web.Components.Core

  alias Phoenix.LiveView.JS
  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Client, Event, PointerTrack}
  alias PhoenixReplay.Web.{Format, Highlight}
  alias PhoenixReplay.Web.Player.{Diff, Events}

  # A value expands only when its row cannot show all of it: when the
  # one-line preview leaves something out, or is longer than a row holds.
  @short_value 40
  # How many changes an assign lists under its row before "and N more".
  @shown_changes 8

  @doc "The icon for an event's type."
  attr :type, :atom, required: true, doc: "a `PhoenixReplay.Recording.Event` type"
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
    <% end %>
    """
  end

  @doc """
  The bar above the player: the way back, what was recorded, its errors
  and a link to the current moment.
  """
  attr :recording, Recording, required: true
  attr :back, :string, required: true, doc: "the recording list's URL"
  attr :duration_ms, :integer, required: true
  attr :error_count, :integer, required: true
  attr :first_error, :integer, default: nil, doc: "the index of the first error"
  attr :dropped, :integer, default: 0
  attr :at, :integer, required: true
  attr :link, :string, required: true, doc: "the URL of the current moment"
  attr :can_delete, :boolean, default: true

  attr :can_export, :boolean,
    default: false,
    doc: "whether the recording can be exported as a video"

  @spec player_header(map()) :: Phoenix.LiveView.Rendered.t()
  def player_header(assigns) do
    ~H"""
    <header class="border-b border-line bg-surface">
      <div class="flex min-h-14 flex-wrap items-center gap-x-3 gap-y-2 px-4 py-2 sm:px-5">
        <.link
          navigate={@back}
          class="inline-flex items-center gap-1 rounded-md py-2 pr-1 text-sm text-muted hover:text-ink"
        >
          <.icon name="lucide:chevron-left" class="size-4" /> Recordings
        </.link>
        <span class="h-5 w-px bg-line" aria-hidden="true"></span>
        <h1 class="truncate text-[15px] font-semibold">{inspect(@recording.view)}</h1>
        <code
          :if={@recording.url}
          class="max-w-56 truncate rounded-md bg-hover px-2 py-0.5 font-mono text-xs text-muted"
        >
          {Format.path_of(@recording.url)}
        </code>
        <span class="text-sm text-muted tabular-nums">
          {Format.started(@recording.connected_at)} · {Format.clock(@duration_ms)} · {Format.count(
            length(@recording.events),
            "event"
          )}
          <span :if={@dropped > 0} title={inspect(@recording.dropped)}>
            · {@dropped} over the limit dropped
          </span>
        </span>
        <button
          :if={@first_error}
          type="button"
          phx-click="seek"
          phx-value-index={@first_error}
          class="inline-flex h-7 items-center gap-1.5 rounded-full bg-error-soft px-2.5 text-xs font-medium text-error transition-colors hover:bg-error/15 pointer-coarse:h-9"
        >
          <span class="size-1.5 rounded-full bg-current"></span>
          {Format.count(@error_count, "error")} · jump to first
        </button>
        <span class="flex-1"></span>
        <.button size="md" data-copy={@link} class="group">
          <.icon name="lucide:link" class="size-4" />
          <span class="group-data-copied:hidden">Copy link to {Format.clock(@at)}</span>
          <span class="hidden group-data-copied:inline">Copied</span>
        </.button>
        <.theme_toggle id="theme-toggle" />
        <.menu :if={@can_delete or @can_export} id="replay-menu" label="More actions">
          <:trigger><.icon name="lucide:ellipsis" class="size-4" /></:trigger>
          <:item :if={@can_export}>
            <button
              id="replay-export"
              type="button"
              phx-click={JS.push("export_dialog") |> close_menu("replay-menu")}
            >
              <.icon name="lucide:clapperboard" class="size-4" /> Export video…
            </button>
          </:item>
          <:item :if={@can_delete} tone="danger">
            <button type="button" phx-click="delete" data-confirm="Delete this recording?">
              <.icon name="lucide:trash-2" class="size-4" /> Delete recording
            </button>
          </:item>
        </.menu>
      </div>
    </header>
    """
  end

  @doc """
  The export dialog: the range of the recording, whether idle stretches
  are shortened and the pointer drawn, the orientation, and the size,
  frame rate and quality of the video. `params` are the form's values,
  as `PhoenixReplay.Export.Options.parse/2` reads them.
  """
  attr :params, :map, required: true
  attr :error, :string, default: nil
  attr :rotatable, :boolean, default: true, doc: "whether the recording has a viewport to rotate"
  attr :max_dpr, :integer, required: true

  @spec export_dialog(map()) :: Phoenix.LiveView.Rendered.t()
  def export_dialog(assigns) do
    ~H"""
    <div
      id="replay-export-dialog"
      class="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4"
      phx-window-keydown="close_export_dialog"
      phx-key="Escape"
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="replay-export-title"
        phx-click-away="close_export_dialog"
        phx-mounted={JS.focus_first()}
        class="w-full max-w-md rounded-xl border border-line bg-surface p-5 text-sm shadow-xl"
      >
        <h2 id="replay-export-title" class="text-base font-semibold">Export video</h2>
        <p class="mt-1 text-muted">An MP4 of the replayed page, as the player shows it.</p>
        <form
          id="replay-export-form"
          phx-change="export_form"
          phx-submit="export"
          class="mt-4 grid grid-cols-[auto_1fr] items-center gap-x-4 gap-y-3"
        >
          <span class="text-muted">Range</span>
          <div class="flex flex-wrap items-center gap-2">
            <.time_field field="from" value={@params["from"]} placeholder="start" />
            <span class="text-muted">to</span>
            <.time_field field="to" value={@params["to"]} placeholder="end" />
            <span class="text-xs text-muted">seconds</span>
          </div>

          <span class="text-muted">Show</span>
          <div class="flex flex-col gap-1.5">
            <.check_field field="skip_idle" params={@params}>Skip inactivity</.check_field>
            <.check_field field="pointer" params={@params} disabled={@params["rotated"] == "true"}>
              The pointer
            </.check_field>
            <.check_field :if={@rotatable} field="rotated" params={@params}>
              Rotated to the other orientation
            </.check_field>
          </div>

          <label for="replay-export-size" class="text-muted">Size</label>
          <.select_field
            id="replay-export-size"
            field="size"
            value={@params["size"]}
            options={[
              {"recorded", "As recorded, up to #{@max_dpr}×"},
              {"1x", "1×"},
              {"half", "Half"}
            ]}
          />

          <label for="replay-export-fps" class="text-muted">Frame rate</label>
          <.select_field
            id="replay-export-fps"
            field="fps"
            value={@params["fps"]}
            options={
              Enum.map(PhoenixReplay.Export.Options.frame_rates(), &{to_string(&1), "#{&1} fps"})
            }
          />

          <label for="replay-export-quality" class="text-muted">Quality</label>
          <.select_field
            id="replay-export-quality"
            field="quality"
            value={@params["quality"]}
            options={[{"small", "Smaller file"}, {"balanced", "Balanced"}, {"best", "Best"}]}
          />

          <p :if={@error} id="replay-export-error" role="alert" class="col-span-2 text-error">
            {@error}
          </p>

          <div class="col-span-2 mt-2 flex justify-end gap-2">
            <button
              type="button"
              phx-click="close_export_dialog"
              class="inline-flex h-9 items-center rounded-md border border-line px-3 hover:bg-hover"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="inline-flex h-9 items-center gap-1.5 rounded-md bg-ink px-3 font-medium text-on-ink hover:opacity-90"
            >
              <.icon name="lucide:clapperboard" class="size-4" /> Export
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end

  attr :field, :string, required: true
  attr :value, :string, default: nil
  attr :placeholder, :string, required: true

  defp time_field(assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-md border border-line bg-surface">
      <input
        id={"replay-export-#{@field}"}
        type="number"
        name={"export[#{@field}]"}
        value={@value}
        min="0"
        step="0.01"
        placeholder={@placeholder}
        aria-label={if @field == "from", do: "From, in seconds", else: "To, in seconds"}
        class="h-8 w-20 rounded-l-md bg-transparent px-2 font-mono tabular-nums outline-none"
      />
      <button
        type="button"
        phx-click="export_at"
        phx-value-field={@field}
        title="The moment the player is at"
        aria-label={"Set #{@field} to the current moment"}
        class="inline-flex h-8 items-center border-l border-line px-1.5 text-muted hover:text-ink"
      >
        <.icon name="lucide:map-pin" class="size-3.5" />
      </button>
    </span>
    """
  end

  attr :field, :string, required: true
  attr :params, :map, required: true
  attr :disabled, :boolean, default: false
  slot :inner_block, required: true

  # An unchecked box sends nothing, so a hidden field sends "false" for it.
  defp check_field(assigns) do
    ~H"""
    <label class={["inline-flex items-center gap-2", @disabled && "opacity-50"]}>
      <input type="hidden" name={"export[#{@field}]"} value="false" />
      <input
        id={"replay-export-#{@field}"}
        type="checkbox"
        name={"export[#{@field}]"}
        value="true"
        checked={@params[@field] == "true" and not @disabled}
        disabled={@disabled}
        class="size-4 accent-[var(--color-accent)]"
      />
      {render_slot(@inner_block)}
    </label>
    """
  end

  attr :id, :string, required: true
  attr :field, :string, required: true
  attr :value, :string, default: nil
  attr :options, :list, required: true

  defp select_field(assigns) do
    ~H"""
    <select
      id={@id}
      name={"export[#{@field}]"}
      class="h-8 rounded-md border border-line bg-surface px-2"
    >
      <option :for={{value, label} <- @options} value={value} selected={value == @value}>
        {label}
      </option>
    </select>
    """
  end

  @doc """
  The state of a video export under the player's header: waiting, its
  progress, a link to the video once it is ready, or why it failed. A
  queued or running export can be cancelled.
  """
  attr :job, PhoenixReplay.Export.Job, required: true
  attr :download, :any, default: nil, doc: "the video's URL once it is ready"

  @spec export_status(map()) :: Phoenix.LiveView.Rendered.t()
  def export_status(assigns) do
    ~H"""
    <div
      id="replay-export-status"
      role="status"
      data-status={@job.status}
      class="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-line bg-chrome px-4 py-2 text-sm sm:px-5"
    >
      <%= case @job.status do %>
        <% :queued -> %>
          <.icon name="lucide:loader-circle" class="size-4 animate-spin text-muted" />
          <span class="text-muted">Waiting to export the video…</span>
        <% :running -> %>
          <.icon name="lucide:loader-circle" class="size-4 animate-spin text-muted" />
          <span>Exporting video</span>
          <div
            role="progressbar"
            aria-label="Export progress"
            aria-valuemin="0"
            aria-valuemax="100"
            aria-valuenow={@job.progress}
            class="h-1.5 w-40 overflow-hidden rounded-full bg-line"
          >
            <div
              class="h-full rounded-full bg-accent transition-[width]"
              style={"width: #{@job.progress}%"}
            >
            </div>
          </div>
          <span class="font-mono text-xs text-muted tabular-nums">{@job.progress}%</span>
        <% :done -> %>
          <.icon name="lucide:circle-check" class="size-4 text-accent" />
          <span>Video ready</span>
          <a
            id="replay-export-download"
            href={@download}
            download
            class="inline-flex h-7 items-center gap-1.5 rounded-md border border-line bg-surface px-2.5 text-xs font-medium hover:bg-hover"
          >
            <.icon name="lucide:download" class="size-3.5" /> Download MP4
          </a>
        <% :cancelling -> %>
          <.icon name="lucide:loader-circle" class="size-4 animate-spin text-muted" />
          <span class="text-muted">Cancelling the export…</span>
        <% :cancelled -> %>
          <.icon name="lucide:circle-slash" class="size-4 text-muted" />
          <span class="text-muted">Export cancelled</span>
        <% :failed -> %>
          <.icon name="lucide:circle-alert" class="size-4 text-error" />
          <span class="text-error">{@job.error}</span>
          <button
            type="button"
            phx-click="export"
            class="inline-flex h-7 items-center rounded-md border border-line bg-surface px-2.5 text-xs font-medium hover:bg-hover"
          >
            Try again
          </button>
      <% end %>
      <span class="flex-1"></span>
      <button
        :if={PhoenixReplay.Export.Job.cancellable?(@job)}
        id="replay-export-cancel"
        type="button"
        phx-click="cancel_export"
        class="inline-flex h-7 items-center rounded-md border border-line bg-surface px-2.5 text-xs font-medium hover:bg-hover"
      >
        Cancel
      </button>
      <button
        :if={PhoenixReplay.Export.Job.finished?(@job)}
        type="button"
        phx-click="dismiss_export"
        aria-label="Dismiss"
        title="Dismiss"
        class="inline-flex size-7 items-center justify-center rounded-md text-muted hover:bg-hover hover:text-ink"
      >
        <.icon name="lucide:x" class="size-4" />
      </button>
    </div>
    """
  end

  @doc """
  The replayed page at the recorded viewport, keeping its aspect ratio:
  fitted to the window or at 100% in a scrolling box. The FrameViewport
  hook writes the sizes into the ignored style element and the scale into
  the ignored label, so the frame itself stays server-rendered. `below`
  names the element kept on screen under it.

  `rotated` swaps the viewport's width and height, so the page lays itself
  out in the other orientation; **Rotate** sends `"rotate"` to toggle it.
  The pointer was recorded in the recorded layout, so it is not drawn, and
  the page not scrolled as recorded, while the frame is rotated.

  When the session recorded scrolling, `follow_scroll` holds the page
  where the user had scrolled: the frame takes no wheel or touch, and the
  overlay puts the recorded position back after every render. **Follow
  scroll** in the view menu sends `"follow_scroll"` to toggle it, leaving
  the page to scroll freely.
  """
  attr :src, :string, required: true
  attr :url, :string, default: nil, doc: "the page URL at the current moment"
  attr :viewport, :map, default: nil
  attr :mode, :string, default: "fit"
  attr :rotated, :boolean, default: false
  attr :follow_scroll, :boolean, default: true
  attr :below, :string, default: nil

  attr :pointer, :map,
    default: nil,
    doc: "the recording's `PhoenixReplay.Recording.PointerTrack` track"

  attr :ready, :boolean,
    default: true,
    doc: "whether the frame's LiveView connected; until then a loader covers it"

  @spec replay_frame(map()) :: Phoenix.LiveView.Rendered.t()
  def replay_frame(assigns) do
    shown = shown_viewport(assigns.viewport, assigns.rotated)

    scrolls? = assigns.pointer != nil and assigns.pointer.scrolls != []

    assigns =
      assign(assigns,
        scrolls?: scrolls?,
        following?: scrolls? and assigns.follow_scroll and not assigns.rotated,
        pointer?: assigns.pointer != nil and PointerTrack.any?(assigns.pointer),
        shown: shown,
        orientation: shown && Format.orientation(shown)
      )

    ~H"""
    <section
      id="replay-viewport"
      aria-label="Replay"
      phx-hook="FrameViewport"
      data-width={@shown && @shown.width}
      data-height={@shown && @shown.height}
      data-mode={@mode}
      data-below={@below}
      class="overflow-hidden rounded-xl border border-line bg-surface"
    >
      <style id="replay-viewport-style" phx-update="ignore">
      </style>
      <%!-- The URL takes the room; the view's controls fold into a menu. --%>
      <div class="@container flex items-center gap-2 border-b border-line bg-chrome px-3 py-2 text-xs text-muted">
        <span
          id="replay-url"
          title={@url}
          class="min-w-[40%] flex-1 truncate rounded-md border border-line bg-surface px-2.5 py-1 font-mono"
        >
          {@url || "—"}
        </span>
        <span
          title="Replayed from recorded assigns: the view renders again, rather than a capture of the screen"
          aria-label="Replayed from recorded assigns"
          class="inline-flex shrink-0"
        >
          <.icon name="lucide:info" class="size-3.5" />
        </span>
        <%!-- The pointer is switched often, so it stays out of the menu. --%>
        <button
          :if={@pointer? and @viewport}
          id="replay-pointer-switch"
          type="button"
          role="switch"
          aria-checked="true"
          aria-label="Pointer"
          disabled={@rotated}
          title={
            if @rotated,
              do: "The pointer was recorded in the other orientation",
              else: "Show the pointer"
          }
          phx-click={
            %JS{}
            |> JS.toggle_class("hidden", to: "#replay-pointer")
            |> JS.toggle_attribute({"aria-checked", "true", "false"})
          }
          class="inline-flex size-7 shrink-0 items-center justify-center rounded-md transition-colors hover:bg-hover hover:text-ink aria-checked:bg-accent/15 aria-checked:text-accent disabled:opacity-40 disabled:hover:bg-transparent pointer-coarse:size-11"
        >
          <.icon name="lucide:mouse-pointer-2" class="size-3.5" />
        </button>
        <.menu
          :if={@viewport}
          id="replay-view"
          label="View"
          trigger_class="inline-flex h-7 shrink-0 items-center gap-1.5 rounded-md border border-line bg-surface px-2 text-muted transition-colors hover:bg-hover hover:text-ink aria-expanded:text-ink pointer-coarse:h-11"
        >
          <:trigger>
            <span
              id="replay-orientation"
              data-orientation={@orientation}
              title={
                if @rotated,
                  do: "Rotated to #{@orientation} from the recorded viewport",
                  else: "The viewport at this moment is #{@orientation}"
              }
              class="inline-flex"
            >
              <.icon
                :if={@orientation == :portrait}
                name="lucide:rectangle-vertical"
                class="size-3.5"
              />
              <.icon
                :if={@orientation == :landscape}
                name="lucide:rectangle-horizontal"
                class="size-3.5"
              />
              <span class="sr-only">{@orientation}</span>
            </span>
            <span
              id="replay-viewport-scale"
              phx-update="ignore"
              data-scale-label
              class="hidden font-mono whitespace-nowrap tabular-nums @[34rem]:inline"
            ></span>
            <.icon name="lucide:chevron-down" class="size-3" />
          </:trigger>
          <:item :for={{value, label} <- [{"fit", "Fit to window"}, {"actual", "Actual size"}]}>
            <button
              type="button"
              role="menuitemradio"
              value={value}
              aria-checked={to_string(value == @mode)}
              phx-click={JS.push("frame_mode", value: %{value: value}) |> close_menu("replay-view")}
              class="group"
            >
              <.icon name="lucide:check" class="size-4 opacity-0 group-aria-checked:opacity-100" />
              {label}
            </button>
          </:item>
          <:item>
            <button
              id="replay-rotate"
              type="button"
              role="menuitemcheckbox"
              aria-checked={to_string(@rotated)}
              title="Show the replay in the other orientation"
              phx-click={JS.push("rotate") |> close_menu("replay-view")}
              class="group"
            >
              <.icon name="lucide:check" class="size-4 opacity-0 group-aria-checked:opacity-100" />
              Rotate
            </button>
          </:item>
          <:item :if={@scrolls?}>
            <button
              id="replay-follow-scroll"
              type="button"
              role="menuitemcheckbox"
              aria-checked={to_string(@following?)}
              disabled={@rotated}
              title={
                if @rotated,
                  do: "The scrolling was recorded in the other orientation",
                  else: "Hold the page where the user had scrolled"
              }
              phx-click={JS.push("follow_scroll") |> close_menu("replay-view")}
              class="group disabled:opacity-40"
            >
              <.icon name="lucide:check" class="size-4 opacity-0 group-aria-checked:opacity-100" />
              Follow scroll
            </button>
          </:item>
        </.menu>
      </div>
      <div id="replay-viewport-box" class="relative bg-canvas">
        <iframe
          id="replay-frame"
          title="Replay"
          src={@src}
          class={["block h-[600px] w-full border-0", @following? && "pointer-events-none"]}
        ></iframe>
        <%!-- Covers the frame while its page loads and its LiveView connects. --%>
        <div
          id="replay-loading"
          role="status"
          data-ready={to_string(@ready)}
          class="pointer-events-none absolute inset-0 z-10 flex items-center justify-center gap-2 bg-canvas text-sm text-muted transition-opacity duration-300 data-[ready=true]:opacity-0"
        >
          <.icon name="lucide:loader-circle" class="size-4 animate-spin" />
          <span>Loading replay…</span>
        </div>
        <%!-- The Pointer hook draws the pointer track over the frame; FrameViewport
             gives it the frame's size, scale and position. --%>
        <div
          :if={@pointer? and @viewport}
          id="replay-pointer"
          phx-hook="Pointer"
          phx-update="ignore"
          data-frame-overlay
          data-track={JSON.encode!(@pointer)}
          data-rotated={@rotated}
          data-follow-scroll={@following?}
          data-width={@viewport.width}
          data-height={@viewport.height}
          aria-hidden="true"
          class="pointer-events-none absolute top-0 left-0"
        >
        </div>
      </div>
    </section>
    """
  end

  defp shown_viewport(%{width: width, height: height} = viewport, true),
    do: %{viewport | width: height, height: width}

  defp shown_viewport(viewport, _rotated), do: viewport

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
        >
          <.icon :if={@playing} name="lucide:pause" class="size-5" />
          <.icon :if={!@playing} name="lucide:play" class="size-5" />
        </.icon_button>
        <.icon_button phx-click="previous" label="Previous event" size="lg" disabled={@index == 0}>
          <.icon name="lucide:chevron-left" class="size-4" />
        </.icon_button>
        <.icon_button phx-click="next" label="Next event" size="lg" disabled={@index == @last}>
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
        />
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
              title={Events.label(event)}
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

  @spec event_list(map()) :: Phoenix.LiveView.Rendered.t()
  def event_list(assigns) do
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
              class="h-full min-w-0 flex-1 bg-transparent text-[13px] outline-none placeholder:text-faint"
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
          <.event_row event={head} current={@index} head />
          <ol :if={rows != []} class="pb-1">
            <li :for={row <- rows}><.event_row event={row} current={@index} /></li>
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
        <.event_icon type={@ev.type} class="size-3.5 shrink-0 opacity-70" />
        <span class="min-w-0 flex-1 truncate font-medium" title={Events.label(@ev)}>
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
  attr :head, :boolean, default: false

  defp event_row(%{event: {event, index}} = assigns) do
    assigns =
      assign(assigns,
        ev: event,
        index: index,
        parts: Events.parts(event)
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
      <.event_icon type={@ev.type} class="size-3.5 shrink-0 opacity-70" />
      <span class="min-w-0 flex-1 truncate" title={Events.label(@ev)}>
        <%= for {kind, content} <- @parts do %>
          <span :if={kind == :text}>{content}</span>
          <code :if={kind == :code} class="font-mono text-xs">{content}</code>
        <% end %>
      </span>
      <span
        :if={duration = Event.duration(@ev)}
        class="shrink-0 font-mono text-[11px] tabular-nums text-muted"
      >
        {Format.milliseconds(duration)}
      </span>
      <span class="shrink-0 font-mono text-[11px] tabular-nums text-muted">
        {Format.clock(@ev.at)}
      </span>
    </button>
    """
  end

  @doc "The view's assigns at the current moment, marking the ones it set."
  attr :assigns, :map, required: true, doc: "the replayed assigns"
  attr :changed, :list, required: true, doc: "the keys the current event set"
  attr :before, :map, default: %{}, doc: "the assigns before the current event"
  attr :at, :integer, required: true

  @spec state(map()) :: Phoenix.LiveView.Rendered.t()
  def state(assigns) do
    %{assigns: values, before: before, changed: changed} = assigns

    rows =
      values
      |> Enum.sort()
      |> Enum.map(fn {key, _value} = assign -> state_row(assign, before, key in changed) end)

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div class="flex items-center justify-between gap-3 border-b border-line px-3.5 py-3">
      <span class="text-sm font-medium">Assigns at {Format.precise_clock(@at)}</span>
      <span :if={@changed != []} class="text-xs text-muted">Changed here are marked</span>
    </div>
    <ul
      id="replay-assigns"
      class="max-h-[calc(100dvh-12rem)] min-h-60 overflow-y-auto py-2 font-mono text-xs"
    >
      <li :for={row <- @rows}>
        <details :if={row.full} class="group">
          <summary class="cursor-pointer list-none">
            <div
              data-assign={row.key}
              class={[
                "grid grid-cols-[0.75rem_minmax(0,8rem)_minmax(0,1fr)] gap-2 px-3.5 py-1.5 hover:bg-hover",
                row.key in @changed && "bg-accent-soft"
              ]}
            >
              <.icon
                name="lucide:chevron-right"
                class="mt-0.5 size-3 text-muted transition-transform group-open:rotate-90"
              />
              <span class={["truncate", row.key in @changed && "text-accent"]}>{row.key}</span>
              <span class="truncate">{row.preview}</span>
            </div>
            <%!-- What changed stays in view whether the value is open or not. --%>
            <.changes :if={row.changes != []} key={row.key} changes={row.changes} more={row.more} />
          </summary>
          <pre
            :if={!row.lines}
            class="mx-3.5 my-1 overflow-x-auto rounded-md bg-canvas p-2.5 leading-relaxed whitespace-pre-wrap text-ink"
          >{row.full}</pre>
          <pre
            :if={row.lines}
            data-diff
            class="mx-3.5 my-1 overflow-x-auto rounded-md bg-canvas py-2 leading-relaxed whitespace-pre-wrap text-ink"
          ><.diff_line :for={line <- row.lines} line={line} /></pre>
        </details>
        <div
          :if={!row.full}
          data-assign={row.key}
          class={[
            "grid grid-cols-[0.75rem_minmax(0,8rem)_minmax(0,1fr)] gap-2 px-3.5 py-1.5",
            row.key in @changed && "bg-accent-soft"
          ]}
        >
          <span></span>
          <span class={["truncate", row.key in @changed && "text-accent"]}>{row.key}</span>
          <span>{row.preview}</span>
        </div>
        <.changes
          :if={!row.full and row.changes != []}
          key={row.key}
          changes={row.changes}
          more={row.more}
        />
      </li>
    </ul>
    """
  end

  @doc """
  Where the session came from: the device, the page before it, the other
  sessions of its browser tab, and the visit's landing and headers.
  """
  attr :recording, Recording, required: true
  attr :viewport, :map, default: nil
  attr :journey, :map, default: nil, doc: "the tab's sessions, with URLs"

  @spec visit(map()) :: Phoenix.LiveView.Rendered.t()
  def visit(%{recording: %{client: client}} = assigns) do
    assigns =
      assign(assigns,
        user_agent: client.user_agent,
        navigated_from: client.navigated_from,
        landing: client.landing,
        headers: client.headers
      )

    ~H"""
    <div class="flex flex-col gap-5 p-4 text-sm">
      <section :if={@viewport || @user_agent} aria-labelledby="replay-device-heading">
        <h3 id="replay-device-heading" class={heading()}>Device</h3>
        <p :if={@viewport} id="replay-device" title={@user_agent}>
          {Format.viewport(@viewport)}<span :if={label = Client.device(@user_agent)}> · {label}</span>
        </p>
        <p :if={!@viewport} title={@user_agent}>
          {Client.device(@user_agent) || "Unknown browser"}
        </p>
      </section>

      <section :if={@journey} id="replay-journey" aria-labelledby="replay-journey-heading">
        <h3 id="replay-journey-heading" class={heading()}>Browser tab</h3>
        <.link navigate={@journey.tab_path} class="underline decoration-line hover:text-ink">
          Session {@journey.position} of {@journey.total} in this tab
        </.link>
        <div class="mt-2 flex gap-3 text-muted">
          <.link
            :if={@journey.previous}
            navigate={@journey.previous}
            class="inline-flex items-center gap-1 hover:text-ink"
          >
            <.icon name="lucide:arrow-left" class="size-3.5" /> Previous
          </.link>
          <.link
            :if={@journey.next}
            navigate={@journey.next}
            class="inline-flex items-center gap-1 hover:text-ink"
          >
            Next <.icon name="lucide:arrow-right" class="size-3.5" />
          </.link>
        </div>
      </section>

      <section :if={@navigated_from} aria-labelledby="replay-navigated-from-heading">
        <h3 id="replay-navigated-from-heading" class={heading()}>Came from</h3>
        <code class="font-mono text-xs break-all" title={@navigated_from}>
          {Format.path_of(@navigated_from)}
        </code>
      </section>

      <section
        :if={@landing || @headers != %{}}
        id="replay-visit"
        aria-labelledby="replay-visit-heading"
      >
        <h3 id="replay-visit-heading" class={heading()}>Visit</h3>
        <div :if={@landing} class="mb-3 flex flex-wrap items-center gap-x-3 gap-y-1 text-muted">
          <.badge :if={Client.campaign(@landing.params)}>{Client.campaign(@landing.params)}</.badge>
          <span :if={Client.referrer_host(@landing.referrer)} title={@landing.referrer}>
            from {Client.referrer_host(@landing.referrer)}
          </span>
          <span>
            landed on <code class="font-mono text-ink">{@landing.path}</code>
            at {Format.timestamp(@landing.at)}
          </span>
        </div>
        <.data_list>
          <:item
            :for={{name, value} <- Enum.sort(if(@landing, do: @landing.params, else: %{}))}
            title={name}
          >
            {value}
          </:item>
          <:item :if={@landing && @landing.referrer} title="referrer">{@landing.referrer}</:item>
          <:item :for={{name, value} <- Enum.sort(@headers)} title={name}>{value}</:item>
        </.data_list>
      </section>

      <section aria-labelledby="replay-session-heading">
        <h3 id="replay-session-heading" class={heading()}>Session</h3>
        <code class="font-mono text-xs break-all">{@recording.id}</code>
      </section>
    </div>
    """
  end

  attr :key, :any, required: true
  attr :changes, :list, required: true
  attr :more, :integer, required: true

  defp changes(assigns) do
    ~H"""
    <ul data-changes={@key} class="mx-3.5 mb-1.5 ml-8 space-y-0.5">
      <li
        :for={{change, path} <- Enum.map(@changes, &{&1, Diff.path(@key, elem(&1, 1))})}
        class="flex min-w-0 items-baseline gap-2"
      >
        <span class={["w-3 shrink-0 text-center", change_class(change)]}>{change_mark(change)}</span>
        <span class="max-w-[70%] shrink-0 truncate text-muted" title={path}>{path}</span>
        <span class="min-w-0 truncate">{change_values(change)}</span>
      </li>
      <li :if={@more > 0} class="ml-5 text-muted">and {@more} more</li>
    </ul>
    """
  end

  attr :line, :any, required: true

  defp diff_line(%{line: {:skip, count}} = assigns) do
    assigns = assign(assigns, :count, count)

    ~H"""
    <span class="block px-2.5 text-faint">⋯ {Format.count(@count, "unchanged line")}</span>
    """
  end

  defp diff_line(%{line: {op, text}} = assigns) do
    assigns = assign(assigns, op: op, text: text)

    ~H"""
    <span data-op={@op} class={["block px-2.5", diff_line_class(@op)]}><span class="mr-2 inline-block w-2 text-muted select-none">{diff_mark(@op)}</span>{@text}</span>
    """
  end

  defp heading, do: "mb-1.5 text-xs font-medium tracking-wide text-muted uppercase"

  defp state_row({key, value}, before, changed?) do
    preview = inspect(value, limit: 8, printable_limit: 80)
    full = inspect(value, pretty: true, limit: 50)
    expand? = full != preview or String.length(preview) > @short_value

    # What the current event changed, when the assign was there before it.
    {changes, lines} =
      case before do
        %{^key => old} when changed? and old != value ->
          {Diff.changes(old, value), if(expand?, do: Diff.lines(old, value, limit: 50))}

        %{} ->
          {[], nil}
      end

    %{
      key: key,
      preview: Highlight.code(preview, :elixir),
      full: if(expand?, do: Highlight.code(full, :elixir)),
      changes: Enum.take(changes, @shown_changes),
      more: max(length(changes) - @shown_changes, 0),
      lines: lines
    }
  end

  defp change_mark({:changed, _path, _old, _new}), do: "~"
  defp change_mark({:added, _path, _new}), do: "+"
  defp change_mark({:removed, _path, _old}), do: "−"

  defp change_class({:changed, _path, _old, _new}), do: "text-accent"
  defp change_class({:added, _path, _new}), do: "text-live"
  defp change_class({:removed, _path, _old}), do: "text-error"

  defp change_values({:changed, _path, old, new}),
    do: [
      Highlight.term(old, limit: 5, printable_limit: 40),
      " → ",
      Highlight.term(new, limit: 5, printable_limit: 40)
    ]

  defp change_values({_op, _path, value}),
    do: Highlight.term(value, limit: 5, printable_limit: 40)

  defp diff_mark(:del), do: "−"
  defp diff_mark(:ins), do: "+"
  defp diff_mark(:eq), do: " "

  defp diff_line_class(:del), do: "bg-error-soft text-error"
  defp diff_line_class(:ins), do: "bg-live-soft text-live"
  defp diff_line_class(:eq), do: nil
end
