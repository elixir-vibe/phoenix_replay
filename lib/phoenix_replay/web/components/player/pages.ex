defmodule PhoenixReplay.Web.Components.Player.Pages do
  @moduledoc """
  The pages of the visit being played, on the visit's clock: one segment
  per page, where it starts and as long as it lasted, pages that overlap,
  as tabs do, in lanes of their own. Each opens its page with the
  `"page"` event; see `PhoenixReplay.Web.Player.Pages`.
  """

  use Phoenix.Component

  import PhoenixIconify, only: [icon: 1]

  alias PhoenixReplay.Web.Format

  @doc """
  The strip of a visit's pages, for a visit of more than one. `gap` is the
  page playback waits to go on to, with how long, between pages.
  """
  attr :pages, :map, required: true
  attr :current, :string, required: true
  attr :gap, :map, default: nil

  @spec visit_pages(map()) :: Phoenix.LiveView.Rendered.t()
  def visit_pages(assigns) do
    assigns = assign(assigns, position: position(assigns.pages, assigns.current))

    ~H"""
    <section
      :if={length(@pages.pages) > 1}
      id="replay-pages"
      aria-label="Pages of this visit"
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
        class="relative"
        style={"height: #{@pages.lanes * 1.25}rem"}
        role="list"
      >
        <button
          :for={page <- @pages.pages}
          id={"replay-page-#{page.id}"}
          type="button"
          role="listitem"
          phx-click="page"
          phx-value-id={page.id}
          aria-current={page.id == @current && "page"}
          title={"#{path(page.url)} · at #{Format.clock(page.offset)}, #{Format.clock(page.end_at - page.offset)}"}
          class={[
            "absolute h-4 min-w-1.5 overflow-hidden rounded px-1 text-left text-[0.625rem] leading-4 whitespace-nowrap transition-colors",
            if(page.id == @current,
              do: "bg-accent-soft font-medium text-accent",
              else: "bg-hover text-muted hover:bg-line hover:text-ink"
            )
          ]}
          style={segment(@pages, page)}
        >
          {path(page.url)}
        </button>
      </div>
    </section>
    """
  end

  defp position(%{pages: pages}, current),
    do: Enum.find_index(pages, &(&1.id == current)) + 1

  # Where the page sits on the visit's clock, and in which lane.
  defp segment(%{duration_ms: duration}, page) do
    total = max(duration, 1)
    left = page.offset / total * 100
    width = (page.end_at - page.offset) / total * 100

    "left: #{Float.round(left, 2)}%; width: #{Float.round(width, 2)}%; top: #{page.lane * 1.25}rem"
  end

  defp path(nil), do: "—"
  defp path(url), do: url |> Format.path_of() |> String.split("?", parts: 2) |> hd()
end
