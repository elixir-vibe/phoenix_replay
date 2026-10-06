defmodule PhoenixReplay.Web.Components.Player.Header do
  @moduledoc """
  The bar above the player: what was recorded, its errors, a link to the
  current moment and the recording's actions. It sends `seek` with an
  `index` to jump to the first error, `export_dialog` and `delete`.

  Like the rest of the player's components, it takes the recording, the
  current position and URLs built by the player, never the socket.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]

  import PhoenixReplay.Web.Components.Core,
    only: [button: 1, close_menu: 2, local_time: 1, menu: 1, theme_toggle: 1]

  import PhoenixReplay.Web.Components.Keys, only: [aria_keyshortcuts: 1, kbd: 1]

  alias Phoenix.LiveView.JS
  alias PhoenixReplay.Recording
  alias PhoenixReplay.Web.Format
  alias PhoenixReplay.Web.Player.Shortcuts

  @doc """
  The bar above the player: the way back, what was recorded, its errors
  and a link to the current moment.
  """
  attr :recording, Recording, required: true
  attr :back, :string, required: true, doc: "the recording list's URL"
  attr :duration_ms, :integer, required: true
  attr :error_count, :integer, required: true
  attr :first_error, :integer, default: nil, doc: "the index of the first error"

  attr :marks, :list,
    default: [],
    doc: "the moments the session reached, from `PhoenixReplay.Web.Player.Events.marks/1`"

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
      <%!-- What was recorded wraps within its own group, so the actions stay
      together on the right, and move below it only on a narrow screen. --%>
      <div class="flex min-h-14 flex-wrap items-center gap-x-3 gap-y-2 px-4 py-2 sm:px-5">
        <div class="flex min-w-0 flex-[1_1_24rem] flex-wrap items-center gap-x-3 gap-y-2">
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
            <.local_time id="replay-started" at={@recording.connected_at}>
              {Format.started(@recording.connected_at)}
            </.local_time>
            · {Format.clock(@duration_ms)} · {Format.count(
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
            aria-keyshortcuts={aria_keyshortcuts(Shortcuts.keys(:next_error))}
            class="inline-flex h-7 items-center gap-1.5 rounded-full bg-error-soft px-2.5 text-xs font-medium text-error transition-colors hover:bg-error/15 pointer-coarse:h-9"
          >
            <span class="size-1.5 rounded-full bg-current"></span>
            {Format.count(@error_count, "error")} · jump to first
            <.kbd keys={hd(Shortcuts.keys(:next_error))} class="ml-0.5" />
          </button>
          <.menu
            :if={@marks != []}
            id="replay-marks"
            label="Marks"
            trigger_class="inline-flex h-7 items-center gap-1.5 rounded-full bg-kind-mark/15 px-2.5 text-xs font-medium text-kind-mark transition-colors hover:bg-kind-mark/25 pointer-coarse:h-9"
          >
            <:trigger>
              <.icon name="lucide:flag" class="size-3.5" />
              {Format.count(length(@marks), "mark")}
              <.kbd keys={hd(Shortcuts.keys(:next_mark))} class="ml-0.5" />
            </:trigger>
            <:item :for={mark <- @marks}>
              <button
                type="button"
                phx-click={JS.push("seek", value: %{index: mark.index}) |> close_menu("replay-marks")}
              >
                <.icon name="lucide:flag" class="size-4 text-kind-mark" />
                <span class="min-w-0 flex-1 truncate">{mark.name}</span>
                <span class="font-mono text-xs text-muted tabular-nums">{Format.clock(mark.at)}</span>
              </button>
            </:item>
          </.menu>
        </div>
        <div class="ml-auto flex shrink-0 items-center gap-x-3">
          <.button size="md" data-copy={@link} class="group">
            <.icon name="lucide:link" class="size-4" />
            <span class="group-data-copied:hidden">Copy link to {Format.precise_clock(@at)}</span>
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
      </div>
    </header>
    """
  end
end
