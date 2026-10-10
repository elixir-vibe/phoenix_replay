defmodule PhoenixReplay.Web.Components.Player.Pages do
  @moduledoc """
  Where playback stands in a visit, next to the player's clock. The
  visit's pages are the first lane of the timeline, in
  `PhoenixReplay.Web.Components.Player.Playback`.
  """

  use Phoenix.Component

  alias PhoenixReplay.Web.Format

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

  defp path(nil), do: "—"
  defp path(url), do: url |> Format.path_of() |> String.split("?", parts: 2) |> hd()
end
