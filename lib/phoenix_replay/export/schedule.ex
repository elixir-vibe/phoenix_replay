defmodule PhoenixReplay.Export.Schedule do
  @moduledoc """
  Which moments of a recording a video shows, and for how long.

  The video runs at a constant frame rate from the first render to the
  end of the recording or its pointer track, and holds the last moment
  for `:hold` milliseconds so it is seen. Each frame shows the moment
  of the recording it falls on, except that a stretch without activity
  longer than `:idle` is shortened to `:idle`, half of it after the
  activity before and half before the activity after.

  Consecutive frames that would look the same share one `t:shot/0`: the
  same event, the same scroll position, the same pointer presses and
  moves, and no pointer animation running. While the pointer moves, and
  for as long as its trail and press ripples take to fade, every frame is
  a shot of its own. So capturing takes a screenshot per shot, not per
  frame.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{PointerTrack, Timeline}

  # How long the player's pointer overlay animates after a move and a
  # press; see `priv/ts/hooks/pointer.ts`.
  @trail_ms 500
  @ripple_ms 600

  # The size a recording without a viewport is shown at.
  @default_viewport %{width: 1280, height: 800, dpr: 1}

  @typedoc """
  One screenshot: the event `index` and the moment `at` of the recording
  to show, the `viewport` the page had, and how many `frames` it lasts.
  """
  @type shot :: %{
          index: non_neg_integer(),
          at: non_neg_integer(),
          viewport: %{width: pos_integer(), height: pos_integer()},
          frames: pos_integer()
        }

  @typedoc """
  The `shots` in order, the `canvas` every viewport fits in, in CSS pixels,
  the device pixel ratio to render at, and the frame rate.
  """
  @type t :: %__MODULE__{
          shots: [shot()],
          canvas: %{width: pos_integer(), height: pos_integer()},
          dpr: number(),
          fps: pos_integer()
        }

  @enforce_keys [:shots, :canvas, :dpr, :fps]
  defstruct @enforce_keys

  @doc """
  Plans the video of a recording laid out by `PhoenixReplay.Recording.Timeline.for_playback/1`
  and its pointer `track`.

  ## Options

    * `:fps` — frames per second (required)
    * `:idle` — milliseconds a stretch without activity is shortened to,
      or `nil` to keep it whole (required)
    * `:max_dpr` — the highest device pixel ratio to render at (required)
    * `:hold` — milliseconds the last moment is held (required)
    * `:from` and `:to` — the range of the recording to show, in
      milliseconds; `nil` for its first render and its end
    * `:rotated` — show every viewport in the other orientation
  """
  @spec new(Recording.t(), PointerTrack.t(), keyword()) :: t()
  def new(%Recording{} = recording, track, opts) do
    fps = Keyword.fetch!(opts, :fps)
    viewports = viewports(recording, Keyword.get(opts, :rotated, false))
    first = Timeline.first_render_index(recording)
    start = max(start_at(recording, first), Keyword.get(opts, :from) || 0)
    ending = max(Timeline.duration_ms(recording), PointerTrack.end_at(track))
    finish = min(ending, Keyword.get(opts, :to) || ending) + Keyword.fetch!(opts, :hold)

    busy = busy(track)
    kept = kept(recording, track, busy, start, finish, Keyword.fetch!(opts, :idle))

    shots =
      kept
      |> moments(fps)
      |> shots(recording, track, busy, first, viewports)

    %__MODULE__{
      shots: shots,
      canvas: canvas(viewports),
      dpr: dpr(recording.client.viewport, Keyword.fetch!(opts, :max_dpr)),
      fps: fps
    }
  end

  @doc "The number of frames in the video."
  @spec frames(t()) :: non_neg_integer()
  def frames(%__MODULE__{shots: shots}), do: Enum.sum_by(shots, & &1.frames)

  @doc "The video's length in milliseconds."
  @spec duration_ms(t()) :: non_neg_integer()
  def duration_ms(%__MODULE__{fps: fps} = schedule), do: div(frames(schedule) * 1_000, fps)

  defp start_at(%Recording{events: []}, _first), do: 0
  defp start_at(%Recording{events: events}, first), do: Enum.at(events, first).at

  # Every viewport the recording had, by event index: the client's until
  # the first `:viewport` event.
  defp viewports(%Recording{events: events, client: client}, rotated?) do
    initial = client.viewport || @default_viewport

    events
    |> Enum.scan(initial, fn
      %{type: :viewport, data: viewport}, _previous -> viewport
      _event, previous -> previous
    end)
    |> Enum.map(&if(rotated?, do: %{&1 | width: &1.height, height: &1.width}, else: &1))
    |> List.to_tuple()
  end

  defp canvas(viewports) do
    viewports = Tuple.to_list(viewports)

    case viewports do
      [] ->
        Map.take(@default_viewport, [:width, :height])

      viewports ->
        %{
          width: viewports |> Enum.map(& &1.width) |> Enum.max(),
          height: viewports |> Enum.map(& &1.height) |> Enum.max()
        }
    end
  end

  defp dpr(%{dpr: dpr}, max_dpr) when is_number(dpr), do: min(dpr, max_dpr)
  defp dpr(_viewport, _max_dpr), do: 1

  # The spans of recording time during which the pointer overlay animates.
  defp busy(%{moves: moves, presses: presses}) do
    (Enum.map(moves, fn [at | _rest] -> {at, at + @trail_ms} end) ++
       Enum.map(presses, fn [at | _rest] -> {at, at + @ripple_ms} end))
    |> merge()
  end

  defp merge(spans) do
    spans
    |> Enum.sort()
    |> Enum.reduce([], fn
      {from, to}, [{previous_from, previous_to} | rest] when from <= previous_to ->
        [{previous_from, max(to, previous_to)} | rest]

      span, acc ->
        [span | acc]
    end)
    |> Enum.reverse()
  end

  # The spans of recording time the video shows, from `start` to `finish`
  # with long stretches without activity cut short.
  defp kept(_recording, _track, _busy, start, finish, nil), do: [{start, finish}]

  defp kept(recording, track, busy, start, finish, idle) do
    activity =
      (Enum.map(recording.events, &{&1.at, &1.at}) ++
         Enum.map(track.scrolls, fn [at | _rest] -> {at, at} end) ++ busy)
      |> Enum.filter(fn {_from, to} -> to >= start end)
      |> merge()

    half = div(idle, 2)

    cuts =
      activity
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [{_from, idle_from}, {idle_to, _to}] ->
        if idle_to - idle_from > idle, do: [{idle_from + half, idle_to - half}], else: []
      end)

    cuts
    |> Enum.reduce({[], start}, fn {from, to}, {kept, at} -> {[{at, from} | kept], to} end)
    |> then(fn {kept, at} -> Enum.reverse([{at, max(at, finish)} | kept]) end)
  end

  # The recording time each frame shows: a frame every 1/fps second of
  # kept time, and at least one.
  defp moments(kept, fps) do
    total = Enum.sum_by(kept, fn {from, to} -> to - from end)
    count = max(1, div(total * fps, 1_000))

    {moments, _rest} =
      Enum.map_reduce(0..(count - 1)//1, {kept, 0}, fn frame, {spans, before} ->
        locate(spans, before, div(frame * 1_000, fps))
      end)

    moments
  end

  # Where `offset` milliseconds into the kept time lands, given the kept
  # time `before` the first of `spans`. Offsets only grow, so the spans
  # passed are dropped.
  defp locate([{from, to} | rest], before, offset)
       when offset - before > to - from and rest != [],
       do: locate(rest, before + to - from, offset)

  defp locate([{from, _to} | _rest] = spans, before, offset),
    do: {from + offset - before, {spans, before}}

  defp shots(moments, recording, track, busy, first, viewports) do
    events =
      recording.events
      |> Enum.with_index()
      |> Enum.map(fn {event, index} -> {event.at, index} end)

    initial = %{
      events: events,
      index: first,
      busy: busy,
      scrolls: track.scrolls,
      scroll: nil,
      presses: track.presses,
      pressed: 0,
      moves: track.moves,
      moved: 0
    }

    {shots, _state} =
      Enum.map_reduce(moments, initial, fn at, state ->
        state = advance(state, at)

        {{key(state, at), %{index: state.index, at: at, viewport: elem(viewports, state.index)}},
         state}
      end)

    shots
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.map(fn [{_key, shot} | _rest] = run ->
      shot
      |> Map.put(:frames, length(run))
      |> Map.update!(:viewport, &Map.take(&1, [:width, :height]))
    end)
  end

  defp advance(state, at) do
    {index, events} = last_before(state.events, at, state.index, fn {_at, index} -> index end)
    {scroll, scrolls} = last_before(state.scrolls, at, state.scroll, &Enum.drop(&1, 1))
    {pressed, presses} = count_before(state.presses, at, state.pressed)
    {moved, moves} = count_before(state.moves, at, state.moved)
    busy = Enum.drop_while(state.busy, fn {_from, to} -> to < at end)

    %{
      state
      | events: events,
        index: max(index, state.index),
        scrolls: scrolls,
        scroll: scroll,
        presses: presses,
        pressed: pressed,
        moves: moves,
        moved: moved,
        busy: busy
    }
  end

  # Frames look alike while the event, the scroll position and the
  # pointer's presses and moves are the same and nothing animates.
  defp key(%{busy: [{from, _to} | _rest]} = state, at) when from <= at,
    do: {state.index, state.scroll, state.pressed, state.moved, at}

  defp key(state, _at), do: {state.index, state.scroll, state.pressed, state.moved}

  defp last_before([sample | rest] = samples, at, last, value) do
    if sample_at(sample) <= at,
      do: last_before(rest, at, value.(sample), value),
      else: {last, samples}
  end

  defp last_before([], _at, last, _value), do: {last, []}

  defp count_before([sample | rest] = samples, at, count) do
    if sample_at(sample) <= at, do: count_before(rest, at, count + 1), else: {count, samples}
  end

  defp count_before([], _at, count), do: {count, []}

  defp sample_at({at, _index}), do: at
  defp sample_at([at | _rest]), do: at
end
