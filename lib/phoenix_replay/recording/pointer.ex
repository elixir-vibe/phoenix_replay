defmodule PhoenixReplay.Recording.Pointer do
  @moduledoc """
  The pointer track of a recording: where the pointer moved, what it
  pressed and how the page scrolled, on the recording's timeline.

  `:pointer` events carry batches the browser sent; see
  `PhoenixReplay.Capture.Pointer`. `split/1` takes them out of a recording,
  so stepping through it stays on LiveView events, and places each sample
  at its offset from the session's start: the batch arrived at its event's
  `at`, and its samples span the `span` milliseconds before that.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Event

  @type t :: %{
          moves: [[integer()]],
          presses: [list()],
          scrolls: [[integer()]]
        }

  @empty %{moves: [], presses: [], scrolls: []}

  @doc "A track with nothing in it."
  @spec empty() :: t()
  def empty, do: @empty

  @doc "The offset of the track's last sample, or `0` for an empty track."
  @spec end_at(t()) :: non_neg_integer()
  def end_at(track) do
    track
    |> Map.values()
    |> Enum.flat_map(&Enum.take(&1, -1))
    |> Enum.map(&hd/1)
    |> Enum.max(fn -> 0 end)
  end

  @doc "Whether the track holds anything to show."
  @spec any?(t()) :: boolean()
  def any?(track), do: track != @empty

  @doc """
  Splits a recording into the recording without its `:pointer` events and
  their track, each list ordered by time:

    * moves `[at, x, y, slot]`
    * presses `[at, kind, x, y, slot, type, target, fx, fy]`
    * scrolls `[at, x, y]`
  """
  @spec split(Recording.t()) :: {Recording.t(), t()}
  def split(%Recording{events: events} = recording) do
    {batches, rest} = Enum.split_with(events, &match?(%Event{type: :pointer}, &1))

    track =
      batches
      |> Enum.reduce(@empty, &add/2)
      |> Map.new(fn {key, samples} -> {key, Enum.sort_by(samples, &hd/1)} end)

    {%{recording | events: rest}, track}
  end

  defp add(%Event{at: at, data: %{span: span} = data}, track) do
    base = max(at - span, 0)

    %{
      moves: chunk(data.moves, 4, base) ++ track.moves,
      presses: Enum.map(data.presses, fn [dt | rest] -> [base + dt | rest] end) ++ track.presses,
      scrolls: chunk(data.scrolls, 3, base) ++ track.scrolls
    }
  end

  defp chunk(flat, stride, base) do
    flat |> Enum.chunk_every(stride) |> Enum.map(fn [dt | rest] -> [base + dt | rest] end)
  end
end
