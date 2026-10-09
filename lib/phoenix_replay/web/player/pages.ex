defmodule PhoenixReplay.Web.Player.Pages do
  @moduledoc """
  The pages of the visit a recording belongs to, for the player: each of
  the visit's recordings the viewer may see, placed on the visit's clock
  by when it started. Pages that overlap, as tabs open side by side do,
  sit in lanes of their own. Playback goes from one page to the next in
  the order they started, waiting out the time between them.

  See `PhoenixReplay.Recording.Visit` for what a visit is; a recording
  without one is a visit of a single page.
  """

  alias PhoenixReplay.{Catalog, Recording}
  alias PhoenixReplay.Recording.Summary
  alias PhoenixReplay.Web.Context

  @typedoc """
  A page: its recording's id, URL and view, when it starts and ends on the
  visit's clock, in milliseconds from the visit's start, its lane, from
  `0`, and whether it is still recording.
  """
  @type page :: %{
          id: Recording.id(),
          url: String.t() | nil,
          view: String.t(),
          offset: non_neg_integer(),
          end_at: non_neg_integer(),
          lane: non_neg_integer(),
          live?: boolean()
        }

  @typedoc "A visit's pages in the order they started, and how long the visit lasted."
  @type t :: %{
          key: String.t(),
          pages: [page()],
          duration_ms: non_neg_integer(),
          lanes: pos_integer()
        }

  @doc "The pages of `recording`'s visit that the viewer may list, `recording` among them."
  @spec of(Phoenix.LiveView.Socket.t(), Recording.t()) :: t()
  def of(socket, %Recording{} = recording) do
    key = recording.client.visit || recording.id

    summaries =
      socket.assigns.context.config
      |> Catalog.visit(key)
      |> Enum.filter(&(&1.id == recording.id or Context.allowed?(socket, :list, &1)))

    summaries =
      if Enum.any?(summaries, &(&1.id == recording.id)),
        do: summaries,
        else: Enum.sort_by([Summary.new(recording) | summaries], &{&1.connected_at, &1.id})

    new(key, summaries)
  end

  @doc "Places `summaries`, all of visit `key`, on the visit's clock."
  @spec new(String.t(), [Summary.t()]) :: t()
  def new(key, summaries) do
    [first | _rest] = summaries = Enum.sort_by(summaries, &{&1.connected_at, &1.id})

    # Lanes by when their latest page ends.
    {pages, ends} =
      Enum.map_reduce(summaries, %{}, fn summary, ends ->
        offset = summary.connected_at - first.connected_at
        end_at = offset + summary.duration_ms
        # The first lane free by the time this page starts, or a new one.
        lane = Enum.find(0..(map_size(ends) - 1)//1, &(ends[&1] <= offset)) || map_size(ends)
        ends = Map.put(ends, lane, end_at)

        {%{
           id: summary.id,
           url: summary.url,
           view: summary.view,
           offset: offset,
           end_at: end_at,
           lane: lane,
           live?: summary.live?
         }, ends}
      end)

    %{
      key: key,
      pages: pages,
      duration_ms: pages |> Enum.map(& &1.end_at) |> Enum.max(),
      lanes: map_size(ends)
    }
  end

  @doc "The page of recording `id`, or `nil`."
  @spec page(t(), Recording.id()) :: page() | nil
  def page(%{pages: pages}, id), do: Enum.find(pages, &(&1.id == id))

  @doc "The page that started after page `id`, or `nil` after the last."
  @spec next(t(), Recording.id()) :: page() | nil
  def next(%{pages: pages}, id) do
    pages |> Enum.drop_while(&(&1.id != id)) |> Enum.drop(1) |> List.first()
  end

  @doc "The page that started before page `id`, or `nil` before the first."
  @spec previous(t(), Recording.id()) :: page() | nil
  def previous(%{pages: pages}, id) do
    pages |> Enum.take_while(&(&1.id != id)) |> Enum.reverse() |> List.first()
  end

  @doc """
  The time between page `from` ending and `to` starting, in milliseconds:
  `0` when `to` started before `from` ended, as an overlapping tab does.
  """
  @spec gap(page(), page()) :: non_neg_integer()
  def gap(from, to), do: max(to.offset - from.end_at, 0)
end
