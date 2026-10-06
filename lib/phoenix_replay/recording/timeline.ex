defmodule PhoenixReplay.Recording.Timeline do
  @moduledoc """
  Navigates a recording's events by index, and knows what the replay
  shows at each: the view's assigns, its LiveComponents' assigns, the page
  URL and the browser viewport.

  A timeline is a cursor. `seek/2` moves it forward by applying only the
  events in between, so playing a recording event by event costs one event
  a step; moving back starts over from the beginning.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Event, PointerTrack, State}

  @state State.assign()

  @typedoc """
  A position in a recording:

    * `:index` — the current event's index, `-1` before the first
    * `:event` — the current event, or `nil`
    * `:assigns` — the view's assigns after it, with the client state
      reported up to it merged into the reserved
      `PhoenixReplay.Recording.State.assign/0`
    * `:before` — the view's assigns before it, which the event changed
      into `:assigns`
    * `:components` — LiveComponent assigns after it, keyed by
      `{module, id}`
    * `:url` — the page URL: the last navigation up to it, or the URL the
      session started on
    * `:viewport` — the last `:viewport` event up to it, or the viewport
      the session connected with, if known
  """
  @type t :: %__MODULE__{
          events: tuple(),
          start: %{url: String.t() | nil, viewport: Recording.viewport() | nil},
          index: integer(),
          event: Event.t() | nil,
          assigns: map(),
          before: map(),
          components: %{{module(), term()} => map()},
          url: String.t() | nil,
          viewport: Recording.viewport() | nil
        }

  @enforce_keys [:events, :start]
  defstruct [
    :events,
    :start,
    :event,
    :url,
    :viewport,
    index: -1,
    assigns: %{@state => %{}},
    before: %{@state => %{}},
    components: %{}
  ]

  @doc """
  Lays a recording out for playback, the same way for the player and its
  frame, so an index means the same event in both: the pointer track is
  taken out, to be drawn over the frame, and client state is spread into
  an event per entry. See `PhoenixReplay.Recording.PointerTrack.split/1`
  and `PhoenixReplay.Recording.State.spread/1`.
  """
  @spec for_playback(Recording.t()) :: {Recording.t(), PointerTrack.t()}
  def for_playback(%Recording{} = recording) do
    {recording, track} = PointerTrack.split(recording)
    {State.spread(recording), track}
  end

  # Events that start an interaction; the rest follow the one before them.
  @starts [:mount, :event, :params, :info]

  @typedoc "An event with its index in the recording."
  @type indexed :: {Event.t(), non_neg_integer()}

  @typedoc "An event that starts an interaction, and the events it caused."
  @type interaction :: {indexed(), [indexed()]}

  @doc """
  Groups events into interactions: a mount, user event, navigation or
  message, followed by the renders, component updates and collected events
  it caused. Events before the first one form an interaction of their own.
  """
  @spec interactions([Event.t()]) :: [interaction()]
  def interactions(events) do
    events
    |> Enum.with_index()
    |> Enum.chunk_while(nil, &interaction/2, &close_interaction/1)
  end

  defp interaction({%Event{type: type}, _index} = item, acc) when type in @starts do
    case acc do
      nil -> {:cont, {item, []}}
      acc -> {:cont, close(acc), {item, []}}
    end
  end

  defp interaction(item, nil), do: {:cont, {item, []}}
  defp interaction(item, {head, rows}), do: {:cont, {head, [item | rows]}}

  defp close_interaction(nil), do: {:cont, nil}
  defp close_interaction(acc), do: {:cont, close(acc), nil}

  defp close({head, rows}), do: {head, Enum.reverse(rows)}

  @doc "A timeline of `recording`, before its first event."
  @spec new(Recording.t()) :: t()
  def new(%Recording{events: events, url: url, client: client}) do
    start = %{url: url, viewport: client.viewport}
    %__MODULE__{events: List.to_tuple(events), start: start, url: url, viewport: client.viewport}
  end

  @doc "A timeline of `recording` at the event at `index`."
  @spec at(Recording.t(), integer()) :: t()
  def at(%Recording{} = recording, index), do: recording |> new() |> seek(index)

  @doc "Moves to the event at `index`, clamped to the recording's range."
  @spec seek(t(), integer()) :: t()
  def seek(%__MODULE__{events: events} = timeline, index) do
    index = index |> max(0) |> min(last_index(timeline))
    from = if index < timeline.index, do: rewind(timeline), else: timeline

    (from.index + 1)..min(index, tuple_size(events) - 1)//1
    |> Enum.reduce(from, &apply_event(&2, elem(events, &1)))
    |> then(&%{&1 | index: index})
  end

  @doc "The event after the current one, or `nil` after the last."
  @spec next(t()) :: Event.t() | nil
  def next(%__MODULE__{events: events, index: index}) when index + 1 < tuple_size(events),
    do: elem(events, index + 1)

  def next(%__MODULE__{}), do: nil

  @doc "Index of the last event, or `0` for an empty recording."
  @spec last_index(Recording.t() | t()) :: non_neg_integer()
  def last_index(%__MODULE__{events: events}), do: max(tuple_size(events) - 1, 0)
  def last_index(%Recording{events: events}), do: max(length(events) - 1, 0)

  @doc "Offset of the last event in milliseconds."
  @spec duration_ms(Recording.t()) :: non_neg_integer()
  def duration_ms(%Recording{events: events}), do: Enum.reduce(events, 0, &max(&1.at, &2))

  @doc """
  Index of the first event after which the view can be rendered.

  The recorder attaches before the view's own `mount/3` runs, so the view's
  assigns first appear with the initial render.
  """
  @spec first_render_index(Recording.t()) :: non_neg_integer()
  def first_render_index(%Recording{events: events}) do
    Enum.find_index(events, &(&1.type == :render)) || 0
  end

  @doc """
  Index of the last event at or before `time`, in milliseconds, but not
  before the first render: where the player stands at that moment.
  """
  @spec index_at(Recording.t(), non_neg_integer()) :: non_neg_integer()
  def index_at(%Recording{events: events} = recording, time) do
    first = first_render_index(recording)
    later = Enum.find_index(events, &(&1.at > time)) || length(events)
    max(later - 1, first)
  end

  defp rewind(%__MODULE__{start: start} = timeline) do
    %{
      timeline
      | index: -1,
        event: nil,
        assigns: %{@state => %{}},
        before: %{@state => %{}},
        components: %{},
        url: start.url,
        viewport: start.viewport
    }
  end

  defp apply_event(timeline, %Event{} = event) do
    timeline = %{timeline | index: timeline.index + 1, event: event, before: timeline.assigns}

    case event do
      %Event{type: :mount, data: %{assigns: assigns}} ->
        %{timeline | assigns: Map.put(assigns, @state, timeline.assigns[@state])}

      %Event{type: :state, data: %{key: _key}} ->
        %{timeline | assigns: Map.update!(timeline.assigns, @state, &State.apply(&1, event))}

      %Event{type: :render, data: %{assigns: assigns}} ->
        %{timeline | assigns: Map.merge(timeline.assigns, assigns)}

      %Event{type: :component, data: %{module: module, id: id, assigns: assigns}} ->
        components =
          Map.update(timeline.components, {module, id}, assigns, &Map.merge(&1, assigns))

        %{timeline | components: components}

      %Event{type: :component_destroyed, data: %{module: module, id: id}} ->
        %{timeline | components: Map.delete(timeline.components, {module, id})}

      %Event{type: :params, data: %{uri: uri}} ->
        %{timeline | url: uri}

      %Event{type: :viewport, data: viewport} ->
        %{timeline | viewport: viewport}

      %Event{} ->
        timeline
    end
  end
end
