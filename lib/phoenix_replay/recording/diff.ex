defmodule PhoenixReplay.Web.Player.Diff do
  @moduledoc """
  What an event changed in an assign, for the player's **State** tab.

  `changes/2` walks the value before and after and names each place that
  differs by its path, such as `tasks[id: "0f4e…"].completed`: map keys,
  struct fields, tuple elements, and list items, matched by their `id`
  when every item has one and by position otherwise. Dates, times,
  decimals and similar values change whole. `lines/2` compares
  the two pretty-printed with `List.myers_difference/2`, for reading the
  whole value with its changes marked.
  """

  @typedoc "A step into a value: a map key or struct field, a list index, or a list item's id."
  @type step :: {:key, term()} | {:index, non_neg_integer()} | {:id, term()}

  @typedoc "One difference, at a path from the assign."
  @type change ::
          {:changed, [step()], term(), term()}
          | {:added, [step()], term()}
          | {:removed, [step()], term()}

  @typedoc "A line of the pretty-printed value: kept, removed or added, or a run of kept lines left out."
  @type line :: {:eq | :del | :ins, String.t()} | {:skip, pos_integer()}

  @context 2

  # Values compared whole: their fields mean nothing apart.
  @whole PhoenixReplay.Recording.Value.opaque_structs()

  @doc "The places where `after_value` differs from `before`, in order."
  @spec changes(term(), term()) :: [change()]
  def changes(before, after_value), do: walk(before, after_value, [])

  @doc """
  The lines of both values pretty-printed with `inspect_opts`, kept lines
  further than #{@context} from a change folded into `{:skip, count}`.
  """
  @spec lines(term(), term(), keyword()) :: [line()]
  def lines(before, after_value, inspect_opts \\ []) do
    split = &(&1 |> inspect([pretty: true] ++ inspect_opts) |> String.split("\n"))

    split.(before)
    |> List.myers_difference(split.(after_value))
    |> Enum.flat_map(fn {op, lines} -> Enum.map(lines, &{op, &1}) end)
    |> fold()
  end

  @doc "Writes a path as Elixir-like access, such as `tasks[id: 7].title` after `name`."
  @spec path(atom() | String.t(), [step()]) :: String.t()
  def path(name, steps), do: Enum.reduce(steps, to_string(name), &step/2)

  defp walk(same, same, _path), do: []

  defp walk(%module{} = before, %module{} = after_value, path) when module not in @whole,
    do: walk_map(Map.from_struct(before), Map.from_struct(after_value), path)

  defp walk(%_{} = before, after_value, path),
    do: [{:changed, Enum.reverse(path), before, after_value}]

  defp walk(before, %_{} = after_value, path),
    do: [{:changed, Enum.reverse(path), before, after_value}]

  defp walk(before, after_value, path) when is_map(before) and is_map(after_value),
    do: walk_map(before, after_value, path)

  defp walk(before, after_value, path) when is_list(before) and is_list(after_value) do
    if identified?(before) and identified?(after_value),
      do: walk_by_id(before, after_value, path),
      else: walk_by_index(before, after_value, path)
  end

  defp walk(before, after_value, path)
       when is_tuple(before) and is_tuple(after_value) and
              tuple_size(before) == tuple_size(after_value),
       do: walk_by_index(Tuple.to_list(before), Tuple.to_list(after_value), path)

  defp walk(before, after_value, path), do: [{:changed, Enum.reverse(path), before, after_value}]

  defp walk_map(before, after_value, path) do
    keys =
      before |> Map.keys() |> Enum.concat(Map.keys(after_value)) |> Enum.uniq() |> Enum.sort()

    Enum.flat_map(keys, fn key ->
      at = [{:key, key} | path]

      case {Map.fetch(before, key), Map.fetch(after_value, key)} do
        {{:ok, old}, {:ok, new}} -> walk(old, new, at)
        {:error, {:ok, new}} -> [{:added, Enum.reverse(at), new}]
        {{:ok, old}, :error} -> [{:removed, Enum.reverse(at), old}]
      end
    end)
  end

  defp walk_by_index(before, after_value, path) do
    common = min(length(before), length(after_value))
    {before, removed} = Enum.split(before, common)
    {after_value, added} = Enum.split(after_value, common)
    at = fn index -> Enum.reverse([{:index, index} | path]) end

    changed =
      before
      |> Enum.zip(after_value)
      |> Enum.with_index()
      |> Enum.flat_map(fn {{old, new}, index} -> walk(old, new, [{:index, index} | path]) end)

    changed ++
      Enum.map(Enum.with_index(removed, common), fn {old, index} ->
        {:removed, at.(index), old}
      end) ++
      Enum.map(Enum.with_index(added, common), fn {new, index} -> {:added, at.(index), new} end)
  end

  defp walk_by_id(before, after_value, path) do
    old = Map.new(before, &{id(&1), &1})
    new = Map.new(after_value, &{id(&1), &1})

    changed_or_removed =
      Enum.flat_map(before, fn item ->
        at = [{:id, id(item)} | path]

        case Map.fetch(new, id(item)) do
          {:ok, now} -> walk(item, now, at)
          :error -> [{:removed, Enum.reverse(at), item}]
        end
      end)

    added =
      for item <- after_value,
          id = id(item),
          not Map.has_key?(old, id),
          do: {:added, Enum.reverse([{:id, id} | path]), item}

    changed_or_removed ++ added
  end

  # Items are matched by id when every one has a distinct id.
  defp identified?([]), do: false

  defp identified?(items) do
    Enum.all?(items, &(id(&1) != nil)) and
      items |> Enum.uniq_by(&id/1) |> length() == length(items)
  end

  defp id(%{id: id}), do: id
  defp id(%{"id" => id}), do: id
  defp id(_item), do: nil

  defp step({:key, key}, acc) when is_atom(key), do: "#{acc}.#{key}"
  defp step({:key, key}, acc), do: "#{acc}[#{inspect(key)}]"
  defp step({:index, index}, acc), do: "#{acc}[#{index}]"
  defp step({:id, id}, acc), do: "#{acc}[id: #{short_id(id)}]"

  # Long ids, such as UUIDs, are told apart by their start.
  defp short_id(id) when is_binary(id) and byte_size(id) > 12,
    do: ~s("#{String.slice(id, 0, 8)}…")

  defp short_id(id), do: inspect(id, limit: 3, printable_limit: 24)

  # Keeps the changed lines and a little context around them.
  defp fold(lines) do
    indexed = Enum.with_index(lines)

    near =
      indexed
      |> Enum.filter(fn {{op, _line}, _index} -> op != :eq end)
      |> Enum.flat_map(fn {_line, index} -> (index - @context)..(index + @context)//1 end)
      |> MapSet.new()

    indexed
    |> Enum.chunk_by(fn {_line, index} -> MapSet.member?(near, index) end)
    |> Enum.flat_map(fn
      [{_line, index} | _rest] = run ->
        if MapSet.member?(near, index),
          do: Enum.map(run, &elem(&1, 0)),
          else: [{:skip, length(run)}]
    end)
  end
end
