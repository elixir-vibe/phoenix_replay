defmodule PhoenixReplay.Recording.Timeline do
  @moduledoc """
  Pure functions for navigating a recording's events by index.
  """

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.Event

  @doc "Offset of the last event in milliseconds."
  @spec duration_ms(Recording.t()) :: non_neg_integer()
  def duration_ms(%Recording{events: events}), do: Enum.reduce(events, 0, &max(&1.at, &2))

  @doc "Index of the last event, or `0` for an empty recording."
  @spec last_index(Recording.t()) :: non_neg_integer()
  def last_index(%Recording{events: events}), do: max(length(events) - 1, 0)

  @doc "Clamps `index` to the recording's valid range."
  @spec clamp(Recording.t(), integer()) :: non_neg_integer()
  def clamp(%Recording{} = recording, index), do: index |> max(0) |> min(last_index(recording))

  @doc "Returns the event at `index`, if any."
  @spec event_at(Recording.t(), non_neg_integer()) :: Event.t() | nil
  def event_at(%Recording{events: events}, index), do: Enum.at(events, index)

  @doc """
  Index of the first event after which the view can be rendered.

  The recorder attaches before the view's own `mount/3` runs, so the view's
  assigns first appear with the initial render.
  """
  @spec first_render_index(Recording.t()) :: non_neg_integer()
  def first_render_index(%Recording{events: events}) do
    Enum.find_index(events, &(&1.type == :render)) || 0
  end

  @doc "Accumulates the assigns visible after the event at `index`."
  @spec assigns_at(Recording.t(), non_neg_integer()) :: map()
  def assigns_at(%Recording{events: events}, index) do
    events
    |> Enum.take(index + 1)
    |> Enum.reduce(%{}, fn
      %Event{type: :mount, data: %{assigns: assigns}}, _acc -> assigns
      %Event{type: :render, data: %{assigns: assigns}}, acc -> Map.merge(acc, assigns)
      %Event{}, acc -> acc
    end)
  end

  @doc """
  Accumulates LiveComponent assigns visible after the event at `index`,
  keyed by `{module, id}`.
  """
  @spec components_at(Recording.t(), non_neg_integer()) :: %{{module(), term()} => map()}
  def components_at(%Recording{events: events}, index) do
    events
    |> Enum.take(index + 1)
    |> Enum.reduce(%{}, fn
      %Event{type: :component, data: %{module: module, id: id, assigns: assigns}}, acc ->
        Map.update(acc, {module, id}, assigns, &Map.merge(&1, assigns))

      %Event{type: :component_destroyed, data: %{module: module, id: id}}, acc ->
        Map.delete(acc, {module, id})

      %Event{}, acc ->
        acc
    end)
  end
end
