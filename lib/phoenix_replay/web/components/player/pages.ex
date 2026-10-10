defmodule PhoenixReplay.Web.Components.Player.Pages do
  @moduledoc """
  The visit in the playback controls: a lane of its pages on the visit's
  clock, the first of the timeline's lanes, and where playback stands in
  it, next to the clock. Each page is a bar where it started and as long
  as it lasted, pages that overlap, as tabs do, in rows of their own, with
  the errors and marks of every page as ticks across them and a playhead
  at the moment playing. The `VisitTimeline` hook moves the playhead
  between the server's updates and sends `"visit_seek"` with the moment
  the pointer let go at; see `PhoenixReplay.Web.Player.Pages`.
  """

  use Phoenix.Component

  alias PhoenixReplay.Web.Format

  @doc """
  The visit's lane. `clock` is where the playhead is, how far it may run
  before the server says more, and whether it plays.
  """
  attr :pages, :map, required: true
  attr :current, :string, required: true
  attr :clock, :map, required: true
  attr :speed, :integer, required: true

  @spec visit_lane(map()) :: Phoenix.LiveView.Rendered.t()
  def visit_lane(assigns) do
    ~H"""
    <div
      id="replay-visit-timeline"
      phx-hook="VisitTimeline"
      role="slider"
      tabindex="0"
      aria-label="Visit time"
      aria-valuemin="0"
      aria-valuemax={@pages.duration_ms}
      aria-valuenow={@clock.at}
      aria-valuetext={"#{Format.clock(@clock.at)} of the visit"}
      data-at={@clock.at}
      data-until={@clock.until}
      data-playing={to_string(@clock.playing?)}
      data-speed={@speed}
      data-duration={@pages.duration_ms}
      class="relative cursor-pointer touch-none rounded select-none"
      style={"height: #{@pages.lanes * 0.5 + 0.25}rem"}
    >
      <span
        :for={marker <- @pages.markers}
        data-marker={marker.kind}
        title={"#{if marker.kind == :error, do: "Error", else: "Mark"} at #{Format.clock(marker.at)}"}
        class={[
          "absolute inset-y-0 w-0.5 -translate-x-1/2 rounded-full",
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
          "absolute h-1.5 min-w-1 rounded-full",
          if(page.id == @current, do: "bg-accent", else: "bg-faint/50 hover:bg-muted")
        ]}
        style={segment(@pages, page)}
      ></span>
      <span
        data-thumb
        aria-hidden="true"
        class="pointer-events-none absolute -inset-y-0.5 w-0.5 -translate-x-1/2 rounded-full bg-ink"
        style={"left: #{percent(@clock.at, @pages)}%"}
      ></span>
    </div>
    """
  end

  @doc """
  Where playback stands in the visit, for next to the clock: the page of
  how many, and between pages, the page it goes on to and when.
  """
  attr :pages, :map, required: true
  attr :current, :string, required: true
  attr :gap, :map, default: nil

  @spec visit_status(map()) :: Phoenix.LiveView.Rendered.t()
  def visit_status(assigns) do
    assigns = assign(assigns, position: position(assigns.pages, assigns.current))

    ~H"""
    <span id="replay-pages" class="text-xs text-muted">
      page {@position} of {length(@pages.pages)}
      <span :if={@gap} id="replay-pages-gap" role="status">
        · {path(@gap.page.url)} in {Format.clock(@gap.ms)}
      </span>
    </span>
    """
  end

  defp position(%{pages: pages}, current),
    do: Enum.find_index(pages, &(&1.id == current)) + 1

  defp percent(at, %{duration_ms: duration}),
    do: Float.round(min(at, duration) / max(duration, 1) * 100, 2)

  # Where the page sits on the visit's clock, and in which row.
  defp segment(pages, page) do
    left = percent(page.offset, pages)
    width = Float.round((page.end_at - page.offset) / max(pages.duration_ms, 1) * 100, 2)
    "left: #{left}%; width: #{width}%; top: #{page.lane * 0.5 + 0.125}rem"
  end

  defp path(nil), do: "—"
  defp path(url), do: url |> Format.path_of() |> String.split("?", parts: 2) |> hd()
end
