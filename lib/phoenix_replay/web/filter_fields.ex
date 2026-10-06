defmodule PhoenixReplay.Web.FilterFields do
  @moduledoc """
  The recording list's filters added with **+ Filter**, in one place: the
  menu lists the ones not set, the bar shows the ones set as chips, and
  the value picker asks for a value by each field's `control`:

    * `:choice` — the values recordings have, with how many have each,
      from `PhoenixReplay.Catalog.values/4`, or any value typed in
    * `:duration` — a number of seconds, typed in or picked from a few
    * `:number` — a number typed in

  A field with `menu: false` is not offered in the menu, but shows as a
  chip when a link sets it, so it can be changed or removed.

  Each field is a criterion of `PhoenixReplay.Recording.Filter` under the
  same name, so the URL, `PhoenixReplay.Trace` and the Mix tasks read it
  as they always have. The search, the time window and the errors toggle
  are in the bar at all times, so they are not listed here.
  """

  alias PhoenixReplay.Recording.Filter
  alias PhoenixReplay.Web.Format

  @type control :: :choice | :duration | :number
  @type t :: %{key: atom(), label: String.t(), control: control(), menu: boolean()}

  @fields [
    %{key: :view, label: "View", control: :choice, menu: true},
    %{key: :event, label: "Event", control: :choice, menu: true},
    %{key: :mark, label: "Mark", control: :choice, menu: true},
    %{key: :source, label: "Source", control: :choice, menu: true},
    %{key: :medium, label: "Medium", control: :choice, menu: true},
    %{key: :campaign, label: "Campaign", control: :choice, menu: true},
    %{key: :device_type, label: "Device", control: :choice, menu: true},
    %{key: :browser, label: "Browser", control: :choice, menu: true},
    %{key: :longer_than, label: "Duration", control: :duration, menu: true},
    %{key: :min_events, label: "Min events", control: :number, menu: false}
  ]

  # Durations offered, in seconds.
  @durations [10, 60, 300]

  @doc "Every field, in the order the menu lists them."
  @spec all() :: [t()]
  def all, do: @fields

  @doc "Reads a field's name sent by the browser."
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(name) do
    case Enum.find(@fields, &(Atom.to_string(&1.key) == name)) do
      nil -> :error
      field -> {:ok, field}
    end
  end

  @doc "The fields `filter` sets, each with its value, in the menu's order."
  @spec set(Filter.t()) :: [{t(), term()}]
  def set(%Filter{} = filter) do
    Enum.flat_map(@fields, fn field ->
      case Map.fetch!(filter, field.key) do
        nil -> []
        value -> [{field, value}]
      end
    end)
  end

  @doc "The fields `filter` does not set yet, for the menu."
  @spec unset(Filter.t()) :: [t()]
  def unset(%Filter{} = filter),
    do: Enum.filter(@fields, &(&1.menu and is_nil(Map.fetch!(filter, &1.key))))

  @doc """
  How a chip reads a field set to `value`, as what comes before the value
  and the value, such as `{"Device is", "Phone"}` or `{"Longer than",
  "1 min"}`.
  """
  @spec describe(t(), term()) :: {String.t(), String.t()}
  def describe(%{control: :duration}, seconds), do: {"Longer than", Format.seconds(seconds)}
  def describe(field, value), do: {field.label <> " is", display(field, value)}

  @doc "A value as the picker and chips show it, such as `\"Phone\"` for `\"phone\"`."
  @spec display(t(), term()) :: String.t()
  def display(%{key: :device_type}, value), do: String.capitalize(value)
  def display(_field, value), do: to_string(value)

  @doc "The durations offered for a `:duration` field, in seconds."
  @spec durations() :: [pos_integer()]
  def durations, do: @durations

  @doc "`filter` without its criterion on `field`."
  @spec without(Filter.t(), t()) :: Filter.t()
  def without(%Filter{} = filter, field), do: Map.put(filter, field.key, nil)

  @doc """
  `filter` with `value` for `field`, read as the URL's parameter is, so a
  value that does not parse, such as a number below one, sets nothing.
  """
  @spec put(Filter.t(), t(), String.t()) :: Filter.t()
  def put(%Filter{} = filter, field, value) do
    filter
    |> Filter.to_params()
    |> Map.put(Atom.to_string(field.key), value)
    |> Filter.from_params()
  end
end
