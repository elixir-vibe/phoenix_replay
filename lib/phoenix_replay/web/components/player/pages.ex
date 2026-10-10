defmodule PhoenixReplay.Web.Components.Player.Pages do
  @moduledoc """
  The visit's timeline: its pages on the visit's clock, one segment per
  page where it started and as long as it lasted, pages that overlap, as
  tabs do, in lanes of their own, with the errors and marks of every page
  above them and a playhead at the moment playing. The `VisitTimeline`
  hook moves the playhead between the server's updates and sends
  `"visit_seek"` with the moment the pointer let go at; see
  `PhoenixReplay.Web.Player.Pages`.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]

  alias PhoenixReplay.Web.Format

  @doc """
  The timeline of a visit of more than one page. `clock` is where the
  playhead is, how far it may run before the server says more, and whether
  it plays; `gap` the page playback waits to go on to, between pages.
  """
  attr :pages, :map, required: true
  attr :current, :string, required: true
  attr :clock, :map, required: true
  attr :speed, :integer, required: true
  attr :gap, :map, default: nil

  @spec visit_pages(map()) :: Phoenix.LiveView.Rendered.t()
  def visit_pages(assigns) do
    assigns = assign(assigns, position: position(assigns.pages, assigns.current))

    ~H"""
    <section
      :if={length(@pages.pages) > 1}
      id="replay-pages"
      aria-label="Visit timeline"
      class="rounded-xl border border-line bg-surface px-3 py-2.5"
    >
      <div class="mb-2 flex items-center justify-between gap-3 text-xs text-muted">
        <span>
          Page {@position} of {length(@pages.pages)} · visit {Format.clock(@pages.duration_ms)}
        </span>
        <span :if={@gap} id="replay-pages-gap" role="status" class="flex items-center gap-1.5">
          <.icon name="lucide:hourglass" class="size-3.5" />
          {path(@gap.page.url)} in {Format.clock(@gap.ms)}
        </span>
      </div>
      <div
        id="replay-visit-timeline"
        phx-hook="VisitTimeline"
        role="slider"
        tabindex="0"
        aria-label="Visit time"
        aria-valuemin="0"
        aria-valuemax={@pages.duration_ms}
        aria-valuenow={@clock.at}
        aria-valuetext={Format.clock(@clock.at)}
        data-at={@clock.at}
        data-until={@clock.until}
        data-playing={to_string(@clock.playing?)}
        data-speed={@speed}
        data-duration={@pages.duration_ms}
        class="relative cursor-pointer touch-none select-none"
        style={"height: #{@pages.lanes * 1.25 + 0.75}rem"}
      >
        <span
          :for={marker <- @pages.markers}
          data-marker={marker.kind}
          title={"#{if marker.kind == :error, do: "Error", else: "Mark"} at #{Format.clock(marker.at)}"}
          class={[
            "absolute top-0 size-1.5 -translate-x-1/2 rounded-full",
            if(marker.kind == :error, do: "bg-error", else: "bg-kind-mark")
          ]}
          style={"left: #{percent(marker.at, @pages)}%"}
        ></span>
        <span
          :for={page <- @pages.pages}
          id={"replay-page-#{page.id}"}
          aria-current={page.id == @current && "page"}
          title={"#{path(page.url)} · at #{Format.clock(page.offset)}, #{Format.clock(page.end_at - page.offset)}"}
          class={[
            "absolute h-4 min-w-1.5 overflow-hidden rounded px-1 text-[0.625rem] leading-4 whitespace-nowrap",
            if(page.id == @current,
              do: "bg-accent-soft font-medium text-accent",
              else: "bg-hover text-muted"
            )
          ]}
          style={segment(@pages, page)}
        >
          {path(page.url)}
        </span>
        <span
          data-thumb
          aria-hidden="true"
          class="pointer-events-none absolute top-0 bottom-0 w-px -translate-x-1/2 bg-ink"
          style={"left: #{percent(@clock.at, @pages)}%"}
        ></span>
      </div>
    </section>
    """
  end

  defp position(%{pages: pages}, current),
    do: Enum.find_index(pages, &(&1.id == current)) + 1

  defp percent(at, %{duration_ms: duration}),
    do: Float.round(min(at, duration) / max(duration, 1) * 100, 2)

  # Where the page sits on the visit's clock, and in which lane, below the markers.
  defp segment(pages, page) do
    left = percent(page.offset, pages)
    width = Float.round((page.end_at - page.offset) / max(pages.duration_ms, 1) * 100, 2)
    "left: #{left}%; width: #{width}%; top: #{page.lane * 1.25 + 0.5}rem"
  end

  defp path(nil), do: "—"
  defp path(url), do: url |> Format.path_of() |> String.split("?", parts: 2) |> hd()
end
