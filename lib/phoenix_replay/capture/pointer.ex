defmodule PhoenixReplay.Capture.Pointer do
  @moduledoc """
  Records the pointer, touches and scrolling the browser sends, when
  `:pointer` is configured.

  `PhoenixReplay.Recorder` tells the browser to record, and with which
  `:pointer` settings, on the connected mount, with its
  `"phx_replay:record"` event. The client module's
  `replayRecorder/1` then samples positions and scroll offsets and sends
  them in batches as an `"phx_replay:pointer"` event, which the recorder
  hands here and halts, so the view never sees it. A batch is:

    * `"span"` — milliseconds from the batch's first sample to sending it
    * `"m"` — moves, flattened `[dt, x, y, slot]` tuples
    * `"p"` — presses, `[dt, kind, x, y, slot, type, target, fx, fy]`:
      `kind` is `0` for down and `1` for up, `type` `0` for a mouse, `1`
      for touch and `2` for a pen, and `target` the id of the pressed
      element, with `fx`, `fy` the point within it in thousandths
    * `"s"` — scroll offsets, flattened `[dt, x, y]` tuples

  `dt` counts milliseconds from the batch's first sample, `x` and `y` are
  CSS pixels in the viewport, and `slot` tells concurrent touches apart.
  Batches come from the browser, so anything malformed is dropped, numbers
  are clamped and each batch holds at most `:max_points` entries. Each is
  recorded as a `:pointer` event, outside `:max_events`, up to `:limit` per
  session.
  """

  alias PhoenixReplay.Config
  alias PhoenixReplay.Session.Buffer

  @event "phx_replay:pointer"
  @max_coordinate 100_000
  @max_target 128

  @doc "The event name batches arrive as."
  @spec event() :: String.t()
  def event, do: @event

  @doc "The settings the browser records with, for `Phoenix.LiveView.push_event/3`."
  @spec settings(Config.pointer()) :: map()
  def settings(pointer), do: Map.take(pointer, [:sample, :scroll, :flush, :max_points])

  @doc "Records a batch sent by the browser for the session `pid` records."
  @spec capture(pid(), map(), Config.pointer()) :: :ok | :dropped | :error
  def capture(pid, params, pointer) do
    with {:ok, session, _sanitizer} <- Buffer.attribute([pid]),
         {:ok, data} <- parse(params, pointer.max_points) do
      Buffer.collect(session, :pointer, data, "pointer", pointer.limit)
    else
      _invalid -> :error
    end
  end

  @doc """
  Validates a batch: returns its moves, presses and scrolls, each within
  `max_points`, or `:error` when nothing usable is in it.
  """
  @spec parse(map(), pos_integer()) :: {:ok, map()} | :error
  def parse(%{"span" => span} = params, max_points) when is_integer(span) and span >= 0 do
    data = %{
      span: min(span, 60_000),
      moves: tuples(params["m"], 4, max_points),
      presses: presses(params["p"], max_points),
      scrolls: tuples(params["s"], 3, max_points)
    }

    if data.moves == [] and data.presses == [] and data.scrolls == [],
      do: :error,
      else: {:ok, data}
  end

  def parse(_params, _max_points), do: :error

  # Flattened integer tuples, kept flat; a list of the wrong length or with
  # anything but integers is dropped whole.
  defp tuples(list, stride, max_points) when is_list(list) do
    if rem(length(list), stride) == 0 and Enum.all?(list, &is_integer/1),
      do: list |> Enum.take(max_points * stride) |> Enum.map(&clamp/1),
      else: []
  end

  defp tuples(_list, _stride, _max_points), do: []

  defp presses(list, max_points) when is_list(list) do
    list |> Enum.take(max_points) |> Enum.flat_map(&press/1)
  end

  defp presses(_list, _max_points), do: []

  defp press([dt, kind, x, y, slot, type, target, fx, fy])
       when is_integer(dt) and kind in [0, 1] and is_integer(x) and is_integer(y) and
              is_integer(slot) and type in [0, 1, 2] and is_integer(fx) and is_integer(fy) do
    [
      [
        clamp(dt),
        kind,
        clamp(x),
        clamp(y),
        clamp(slot),
        type,
        target(target),
        share(fx),
        share(fy)
      ]
    ]
  end

  defp press(_press), do: []

  defp target(id) when is_binary(id) and id != "", do: String.slice(id, 0, @max_target)
  defp target(_id), do: nil

  defp clamp(value), do: value |> max(-@max_coordinate) |> min(@max_coordinate)
  defp share(value), do: value |> max(0) |> min(1_000)
end
