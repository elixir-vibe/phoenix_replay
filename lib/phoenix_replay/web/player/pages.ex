defmodule PhoenixReplay.Web.Player.Pages do
  @moduledoc """
  The pages of the visit a recording belongs to, for the player: each of
  the visit's recordings the viewer may see, placed on the visit's clock
  by when it started. Pages that overlap, as tabs open side by side do,
  sit in lanes of their own. Playback follows the visit's clock: when a
  page ends, it goes on in a tab still open at that moment, or waits out
  the time until the next page started; see `after_page/2`.

  See `PhoenixReplay.Recording.Visit` for what a visit is; a recording
  without one is a visit of a single page.
  """

  alias PhoenixReplay.{Catalog, Recording}
  alias PhoenixReplay.Recording.{Event, Summary, Timeline}
  alias PhoenixReplay.Web.Context
  alias PhoenixReplay.Web.Player.Events

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

  @typedoc """
  The events of one kind across the visit's pages, for the player's lanes:
  each with its time moved onto the visit's clock, and its page's id.
  """
  @type lane :: {Events.kind(), [{Event.t(), Recording.id()}]}

  @typedoc """
  A visit's pages in the order they started, how long the visit lasted,
  how many rows its pages take, and the events of all its pages by kind.
  """
  @type t :: %{
          key: String.t(),
          pages: [page()],
          duration_ms: non_neg_integer(),
          lanes: pos_integer(),
          events: [lane()]
        }

  @doc "The visit `recording` belongs to: its `client.visit`, or its own id."
  @spec key(Recording.t()) :: String.t()
  def key(%Recording{} = recording), do: recording.client.visit || recording.id

  @doc "The pages of `recording`'s visit that the viewer may list, `recording` among them."
  @spec of(Phoenix.LiveView.Socket.t(), Recording.t()) :: t()
  def of(socket, %Recording{} = recording) do
    key = key(recording)

    summaries =
      socket.assigns.context.config
      |> Catalog.visit(key)
      |> Enum.filter(&(&1.id == recording.id or Context.allowed?(socket, :list, &1)))

    summaries =
      if Enum.any?(summaries, &(&1.id == recording.id)),
        do: summaries,
        else: Enum.sort_by([Summary.new(recording) | summaries], &{&1.connected_at, &1.id})

    visit = new(key, summaries)

    if length(visit.pages) > 1,
      do: %{visit | events: events(socket, visit, recording)},
      else: visit
  end

  # The events of every page, as the player lays out a recording, on the
  # visit's clock, in the order of the kinds' lanes.
  defp events(socket, visit, recording) do
    by_page =
      for page <- visit.pages,
          {:ok, read} <- [read(socket, page, recording)],
          {playback, _pointer} = Timeline.for_playback(read),
          {kind, events} <- Events.lanes(playback),
          {event, _index} <- events,
          do: {kind, {%{event | at: event.at + page.offset}, page.id}}

    by_page
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(fn {kind, _events} -> Enum.find_index(Events.kind_order(), &(&1 == kind)) end)
  end

  defp read(_socket, %{id: id}, %Recording{id: id} = recording), do: {:ok, recording}

  defp read(socket, page, _recording),
    do: Catalog.fetch(socket.assigns.context.config, page.id)

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
      lanes: map_size(ends),
      events: []
    }
  end

  @doc "The page of recording `id`, or `nil`."
  @spec page(t(), Recording.id()) :: page() | nil
  def page(%{pages: pages}, id), do: Enum.find(pages, &(&1.id == id))

  @doc """
  Where playback goes when page `id` ends, at that moment on the visit's
  clock:

    * `{:continue, page, at}` — another tab still open then, at `at`
      milliseconds into it
    * `{:wait, page, gap}` — nothing open then; the next page to start,
      `gap` milliseconds later
    * `nil` — nothing open then, and no page started later

  A tab that opened and closed while page `id` played is not gone back to;
  the strip opens it.
  """
  @spec after_page(t(), Recording.id()) ::
          {:continue, page(), non_neg_integer()} | {:wait, page(), non_neg_integer()} | nil
  def after_page(%{pages: pages} = visit, id) do
    %{end_at: ended} = page(visit, id)

    case Enum.find(pages, &(&1.id != id and &1.offset < ended and &1.end_at > ended)) do
      %{} = open ->
        {:continue, open, ended - open.offset}

      nil ->
        case Enum.find(pages, &(&1.id != id and &1.offset >= ended)) do
          %{} = next -> {:wait, next, next.offset - ended}
          nil -> nil
        end
    end
  end

  @doc "The page that started before page `id`, or `nil` before the first."
  @spec previous(t(), Recording.id()) :: page() | nil
  def previous(%{pages: pages}, id) do
    pages |> Enum.take_while(&(&1.id != id)) |> Enum.reverse() |> List.first()
  end

  @doc """
  The page to show at `at` milliseconds into the visit, and how far into
  it: the page `current` when it is open then, else the page open then in
  the lowest lane, else the next page to start, from its start. Past the
  last page, its end.
  """
  @spec at(t(), integer(), Recording.id()) :: {page(), non_neg_integer()}
  def at(%{pages: pages}, at, current) do
    open = Enum.filter(pages, &(&1.offset <= at and at < &1.end_at))

    case {Enum.find(open, &(&1.id == current)), Enum.min_by(open, & &1.lane, fn -> nil end)} do
      {%{} = page, _lowest} ->
        {page, at - page.offset}

      {nil, %{} = page} ->
        {page, at - page.offset}

      {nil, nil} ->
        case Enum.find(pages, &(&1.offset > at)) do
          %{} = next -> {next, 0}
          nil -> pages |> Enum.max_by(& &1.end_at) |> then(&{&1, &1.end_at - &1.offset})
        end
    end
  end
end
