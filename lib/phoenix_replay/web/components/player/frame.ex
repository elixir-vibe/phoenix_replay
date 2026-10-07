defmodule PhoenixReplay.Web.Components.Player.Frame do
  @moduledoc """
  The replayed page in its frame, with the bar above it: the URL, the
  pointer switch and the **View** menu. It sends `frame_mode` with a
  `value`, `rotate` and `follow_scroll`.

  Like the rest of the player's components, it takes the recording, the
  current position and URLs built by the player, never the socket.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]

  import PhoenixReplay.Web.Components.Core, only: [close_menu: 2, menu: 1, tooltip: 1]
  import PhoenixReplay.Web.Components.Keys, only: [aria_keyshortcuts: 1, kbd: 1]

  alias Phoenix.LiveView.JS
  alias PhoenixReplay.Recording.{Client, PointerTrack}
  alias PhoenixReplay.Web.Player.Shortcuts

  @doc """
  The replayed page at the recorded viewport, keeping its aspect ratio:
  fitted to the window or at 100% in a scrolling box. The FrameViewport
  hook writes the sizes into the ignored style element and the scale into
  the ignored label, so the frame itself stays server-rendered.

  When the recording turns between portrait and landscape, the device is
  shown turning. `rotated` turns the shown device a quarter turn, to look
  at it the other way round, with the page, the pointer and the scrolling
  as recorded; **Rotate** sends `"rotate"` to toggle it.

  The replayed page takes the recorded color scheme: the frame's
  `color-scheme`, which Safari's `prefers-color-scheme` follows, and the
  FrameColorScheme hook, which rewrites the page's media rules for the
  browsers that do not.

  When the session recorded scrolling, `follow_scroll` holds the page
  where the user had scrolled: the frame takes no wheel or touch, and the
  overlay puts the recorded position back after every render. **Follow
  scroll** in the view menu sends `"follow_scroll"` to toggle it, leaving
  the page to scroll freely.
  """
  attr :src, :string, default: nil, doc: "the frame's address; without one it loads nothing yet"
  attr :url, :string, default: nil, doc: "the page URL at the current moment"
  attr :viewport, :map, default: nil
  attr :mode, :string, default: "fit"
  attr :rotated, :boolean, default: false
  attr :follow_scroll, :boolean, default: true

  attr :pointer, :map,
    default: nil,
    doc: "the recording's `PhoenixReplay.Recording.PointerTrack` track"

  attr :ready, :boolean,
    default: true,
    doc: "whether the frame's LiveView connected; until then a loader covers it"

  attr :unrecorded, :list,
    default: [],
    doc: "assigns the template reads that the recording lacks, shown as nil"

  attr :code_changes, :map,
    default: %{modules: [], deps: []},
    doc:
      "what changed in the code since the recording, from `PhoenixReplay.Recording.Code.changes/1`"

  @spec replay_frame(map()) :: Phoenix.LiveView.Rendered.t()
  def replay_frame(assigns) do
    viewport = assigns.viewport
    scrolls? = assigns.pointer != nil and assigns.pointer.scrolls != []

    assigns =
      assign(assigns,
        scrolls?: scrolls?,
        following?: scrolls? and assigns.follow_scroll,
        pointer?: assigns.pointer != nil and PointerTrack.any?(assigns.pointer),
        orientation: viewport && Client.orientation(viewport),
        color_scheme: viewport && viewport[:color_scheme],
        media: Client.media(viewport)
      )

    ~H"""
    <section
      id="replay-viewport"
      aria-label="Replay"
      phx-hook="FrameViewport"
      data-width={@viewport && @viewport.width}
      data-height={@viewport && @viewport.height}
      data-angle={@viewport && @viewport[:angle]}
      data-turn={@rotated}
      data-mode={@mode}
      class="flex flex-col overflow-hidden rounded-xl border border-line bg-surface lg:min-h-0 lg:flex-1"
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
        <%!-- Today's code renders the replay, so what changed since is told. --%>
        <.tooltip
          :if={@code_changes != %{modules: [], deps: []}}
          label={changed_label(@code_changes)}
          position="bottom"
        >
          <span
            id="replay-code-changed"
            tabindex="0"
            class="inline-flex shrink-0 items-center gap-1 rounded-md bg-slow/10 px-2 py-1 text-slow"
          >
            <.icon name="lucide:git-compare" class="size-3.5" /> Code changed
          </span>
        </.tooltip>
        <%!-- The template reads assigns the recording lacks; the page shows
        them unset. --%>
        <.tooltip :if={@unrecorded != []} label={unrecorded_label(@code_changes)} position="bottom">
          <span
            id="replay-unrecorded"
            tabindex="0"
            class="inline-flex shrink-0 items-center gap-1 rounded-md bg-slow/10 px-2 py-1 text-slow"
          >
            <.icon name="lucide:circle-dashed" class="size-3.5" />
            Not in recording: {Enum.map_join(@unrecorded, ", ", &"@#{&1}")}
          </span>
        </.tooltip>
        <span
          title="Replayed from recorded assigns: the view renders again, rather than a capture of the screen"
          aria-label="Replayed from recorded assigns"
          class="inline-flex shrink-0"
        >
          <.icon name="lucide:info" class="size-3.5" />
        </span>
        <%!-- The pointer is switched often, so it stays out of the menu. --%>
        <.tooltip
          :if={@pointer? and @viewport}
          label="Show the pointer"
          keys={Shortcuts.keys(:pointer)}
          position="bottom"
        >
          <button
            id="replay-pointer-switch"
            type="button"
            role="switch"
            aria-checked="true"
            aria-label="Pointer"
            aria-keyshortcuts={aria_keyshortcuts(Shortcuts.keys(:pointer))}
            phx-click={
              %JS{}
              |> JS.toggle_class("hidden", to: "#replay-pointer")
              |> JS.toggle_attribute({"aria-checked", "true", "false"})
            }
            class="inline-flex size-7 shrink-0 items-center justify-center rounded-md transition-colors hover:bg-hover hover:text-ink aria-checked:bg-accent/15 aria-checked:text-accent pointer-coarse:size-11"
          >
            <.icon name="lucide:mouse-pointer-2" class="size-3.5" />
          </button>
        </.tooltip>
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
                  do: "The #{@orientation} viewport of this moment, turned to look at",
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
              aria-keyshortcuts={value != @mode && aria_keyshortcuts(Shortcuts.keys(:fit))}
              phx-click={JS.push("frame_mode", value: %{value: value}) |> close_menu("replay-view")}
              class="group"
            >
              <.icon name="lucide:check" class="size-4 opacity-0 group-aria-checked:opacity-100" />
              {label}
              <%!-- F switches to the other mode. --%>
              <.kbd :if={value != @mode} keys={hd(Shortcuts.keys(:fit))} class="ml-auto" />
            </button>
          </:item>
          <:item>
            <button
              id="replay-rotate"
              type="button"
              role="menuitemcheckbox"
              aria-checked={to_string(@rotated)}
              aria-keyshortcuts={aria_keyshortcuts(Shortcuts.keys(:rotate))}
              title="Turn the device to look at it the other way round"
              phx-click={JS.push("rotate") |> close_menu("replay-view")}
              class="group"
            >
              <.icon name="lucide:check" class="size-4 opacity-0 group-aria-checked:opacity-100" />
              Rotate <.kbd keys={hd(Shortcuts.keys(:rotate))} class="ml-auto" />
            </button>
          </:item>
          <:item :if={@scrolls?}>
            <button
              id="replay-follow-scroll"
              type="button"
              role="menuitemcheckbox"
              aria-checked={to_string(@following?)}
              title="Hold the page where the user had scrolled"
              phx-click={JS.push("follow_scroll") |> close_menu("replay-view")}
              class="group"
            >
              <.icon name="lucide:check" class="size-4 opacity-0 group-aria-checked:opacity-100" />
              Follow scroll
            </button>
          </:item>
        </.menu>
      </div>
      <%!-- Side by side, the box takes the height the player leaves it, and
      FrameViewport scales the replay to it; see --frame-fill. --%>
      <div
        id="replay-viewport-box"
        class="relative bg-canvas lg:min-h-0 lg:flex-1 lg:[--frame-fill:1]"
      >
        <iframe
          id="replay-frame"
          title="Replay"
          src={@src}
          phx-hook="FrameMedia"
          data-media={JSON.encode!(@media)}
          style={@color_scheme && "color-scheme: #{@color_scheme}"}
          class={["block h-[600px] w-full border-0 lg:h-full", @following? && "pointer-events-none"]}
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
          data-trail={PointerTrack.trail_ms()}
          data-ripple={PointerTrack.ripple_ms()}
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

  defp changed_label(%{modules: modules, deps: deps}) do
    modules = Enum.map(modules, &inspect/1)
    deps = for {dep, then, now} <- deps, do: "#{dep} #{then} → #{now || "removed"}"
    "Changed since recorded: #{Enum.join(modules ++ deps, ", ")}"
  end

  # Why the recording lacks them: the code changed since, or, with the
  # same code, the sanitizer left them out.
  defp unrecorded_label(%{modules: []}),
    do: "Missing from the recording, as your sanitizer may leave out: shown unset"

  defp unrecorded_label(_changes), do: "Added since this was recorded: shown unset"
end
