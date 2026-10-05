defmodule PhoenixReplay.Recording.State do
  @moduledoc """
  Client state on a recording's timeline.

  `:state` events are stored as the batches the browser sent; see
  `PhoenixReplay.Capture.State`. `spread/1` turns each into one `:state`
  event per entry, `%{key: String.t(), changes: map}`, at its own offset
  from the session's start: the batch arrived at its event's `at`, and its
  entries span the `span` milliseconds before that. The player then steps
  through them like any other event, and `PhoenixReplay.Recording.Timeline`
  merges each entry's changes into the `#{inspect(:phoenix_replay_state)}`
  assign, `%{key => merged changes}`, which a view's `replay_render/1`
  reads. See `assign/0`.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Event

  @assign :phoenix_replay_state

  @doc """
  The reserved assign the replayed state is merged into: a map of each
  key's merged changes, with string keys, empty before any state.
  """
  @spec assign() :: atom()
  def assign, do: @assign

  @doc """
  Places each entry of the recording's `:state` batches on its timeline as
  a `:state` event of its own. The other events keep their order; an entry
  goes before the first of them that happened after it. Recordings already
  spread are returned as they are.
  """
  @spec spread(Recording.t()) :: Recording.t()
  def spread(%Recording{events: events} = recording) do
    {batches, rest} =
      Enum.split_with(events, &match?(%Event{type: :state, data: %{entries: _}}, &1))

    case batches do
      [] ->
        recording

      batches ->
        %{
          recording
          | events: merge(rest, batches |> Enum.flat_map(&entries/1) |> Enum.sort_by(& &1.at))
        }
    end
  end

  @doc "Merges a `:state` event's changes into the state replayed so far."
  @spec apply(map(), Event.t()) :: map()
  def apply(state, %Event{type: :state, data: %{key: key, changes: changes}}),
    do: Map.update(state, key, changes, &Map.merge(&1, changes))

  defp entries(%Event{at: at, data: %{span: span, entries: entries}}) do
    base = max(at - span, 0)

    for [dt, key, changes] <- entries,
        do: %Event{at: base + dt, type: :state, data: %{key: key, changes: changes}}
  end

  defp merge([event | events], [entry | entries]) when entry.at < event.at,
    do: [entry | merge([event | events], entries)]

  defp merge([event | events], entries), do: [event | merge(events, entries)]
  defp merge([], entries), do: entries
end
