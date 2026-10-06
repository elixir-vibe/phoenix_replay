defmodule PhoenixReplay.Web.Player.Events do
  @moduledoc """
  How the player presents a recording's events: their labels, the kinds
  the event list filters by, and their timeline markers.
  """

  alias PhoenixReplay.Collector
  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Client, Event, Label, State, Timeline}
  alias PhoenixReplay.Web.{Format, Highlight}

  @typedoc "What the event list filters by."
  @type kind :: :liveview | :state | :telemetry | :logs

  @kinds [:liveview, :state, :telemetry, :logs]

  # Errors stand out: larger, red, with a soft ring.
  @error_marker "size-2.5 bg-error ring-3 ring-error-soft"

  @doc "The kind an event type is filtered as."
  @spec kind(Event.type()) :: kind()
  def kind(:state), do: :state
  def kind(:telemetry), do: :telemetry
  def kind(:log), do: :logs
  def kind(_type), do: :liveview

  @doc "Reads a kind sent by the browser, or returns `:error`."
  @spec parse_kind(String.t()) :: {:ok, kind()} | :error
  def parse_kind(name) do
    case Enum.find(@kinds, &(Atom.to_string(&1) == name)) do
      nil -> :error
      kind -> {:ok, kind}
    end
  end

  @doc "The kinds in a recording, LiveView first."
  @spec kinds(Recording.t()) :: [kind()]
  def kinds(%Recording{events: events}) do
    events
    |> Enum.map(&kind(&1.type))
    |> Enum.uniq()
    |> Enum.sort_by(&(&1 != :liveview))
  end

  @typedoc "What the event list shows: hidden kinds, a search, and errors only."
  @type filters :: %{hidden: MapSet.t(kind()), query: String.t(), errors_only: boolean()}

  @doc """
  Keeps the events of `PhoenixReplay.Recording.Timeline.interactions/1` that `filters` show. An interaction
  stays while any of its events does, or its own first event.
  """
  @spec visible([Timeline.interaction()], filters()) :: [Timeline.interaction()]
  def visible(interactions, filters) do
    Enum.flat_map(interactions, fn {{head, _index} = first, rows} ->
      case Enum.filter(rows, fn {event, _index} -> visible?(event, filters) end) do
        [] -> if visible?(head, filters), do: [{first, []}], else: []
        rows -> [{first, rows}]
      end
    end)
  end

  @doc "The events of each kind in a recording, as timeline lanes."
  @spec lanes(Recording.t()) :: [{kind(), [Timeline.indexed()]}]
  def lanes(%Recording{events: events} = recording) do
    indexed = Enum.with_index(events)

    for kind <- kinds(recording),
        do: {kind, Enum.filter(indexed, &(kind(elem(&1, 0).type) == kind))}
  end

  @doc "How many events of each kind a recording has."
  @spec kind_counts(Recording.t()) :: %{kind() => non_neg_integer()}
  def kind_counts(%Recording{events: events}), do: Enum.frequencies_by(events, &kind(&1.type))

  @doc "The colour class of a kind's swatch."
  @spec kind_class(kind()) :: String.t()
  def kind_class(:liveview), do: "bg-kind-event"
  def kind_class(:state), do: "bg-kind-component"
  def kind_class(:telemetry), do: "bg-kind-query"
  def kind_class(:logs), do: "bg-kind-log"

  @doc "The index of the first event that reports an error, or `nil`."
  @spec first_error_index(Recording.t()) :: non_neg_integer() | nil
  def first_error_index(%Recording{events: events}), do: Enum.find_index(events, &Event.error?/1)

  @doc "The index of the nearest event after or before `index` that reports an error, or `nil`."
  @spec error_index(Recording.t(), non_neg_integer(), :next | :previous) ::
          non_neg_integer() | nil
  def error_index(%Recording{events: events}, index, direction) do
    errors = for {event, at} <- Enum.with_index(events), Event.error?(event), do: at

    case direction do
      :next -> Enum.find(errors, &(&1 > index))
      :previous -> errors |> Enum.reverse() |> Enum.find(&(&1 < index))
    end
  end

  @doc "Whether an event's label contains `query`, ignoring case."
  @spec matches?(Event.t(), String.t()) :: boolean()
  def matches?(_event, ""), do: true

  def matches?(event, query),
    do: event |> Event.label() |> String.downcase() |> String.contains?(String.downcase(query))

  @doc """
  Name–value pairs describing an event in full, for the details pane:
  what was called with which params, the assigns a render or component
  set, the query, log or crash, the client state or the viewport. Values
  that are code or Elixir terms come highlighted.
  """
  @spec details(Event.t()) :: [{String.t(), String.t() | Phoenix.HTML.safe()}]
  def details(%Event{type: :mount, data: %{assigns: assigns}}), do: [{"Assigns", term(assigns)}]

  def details(%Event{type: :event, data: %{name: name, params: params} = data}) do
    present([
      {"Event", name},
      {"Component", with({module, id} <- data[:target], do: Label.component(module, id))},
      {"Params", term(params)}
    ])
  end

  def details(%Event{type: :params, data: %{uri: uri} = data}),
    do: present([{"URL", uri}, {"Params", data |> Map.get(:params) |> term()}])

  def details(%Event{type: :info, data: %{tag: nil}}),
    do: [{"Message", "Not a tagged tuple; only a message's tag is kept"}]

  def details(%Event{type: :info, data: %{tag: tag}}), do: [{"Message tag", term(tag)}]

  def details(%Event{type: :render, data: %{assigns: assigns}}), do: [{"Assigns", term(assigns)}]

  def details(%Event{type: :component, data: %{module: module, id: id, assigns: assigns}}),
    do: [{"Component", Label.component(module, id)}, {"Assigns", term(assigns)}]

  def details(%Event{type: :component_destroyed, data: %{module: module, id: id}}),
    do: [{"Component", Label.component(module, id)}]

  def details(%Event{type: :viewport, data: %{width: width, height: height} = viewport}) do
    present([
      {"Size", "#{width} × #{height}"},
      {"Orientation", viewport |> Client.orientation() |> Atom.to_string()},
      {"Pixel ratio", with(dpr when is_number(dpr) <- viewport[:dpr], do: "#{dpr}")}
    ])
  end

  def details(%Event{type: :state, data: %{key: key, changes: changes}}) do
    if key == State.inputs_key(),
      do: [{"Form controls", term(changes)}],
      else: [{"Key", key}, {"Changes", term(changes)}]
  end

  def details(%Event{type: :telemetry, data: data} = event) do
    present([
      {"Event", Collector.name(data.event)},
      {"Summary", summary(data)},
      {"Duration", event |> Event.duration() |> duration()},
      {"Error", data.error},
      {"Metadata", metadata(data.metadata)}
    ])
  end

  def details(%Event{type: :log, data: data}) do
    present([
      {"Level", to_string(data.level)},
      {"Message", data.message},
      {"Metadata", metadata(data.metadata)}
    ])
  end

  def details(%Event{type: :exit, data: %{reason: reason}}), do: [{"Reason", reason}]
  def details(%Event{}), do: []

  @doc "A kind's name in the filter."
  @spec kind_label(kind()) :: String.t()
  def kind_label(:liveview), do: "LiveView"
  def kind_label(:state), do: "Client state"
  def kind_label(:telemetry), do: "Telemetry"
  def kind_label(:logs), do: "Logs"

  @doc """
  Whether an event was collected from telemetry or logs. Collected events
  follow the LiveView event that caused them.
  """
  @spec collected?(Event.t()) :: boolean()
  def collected?(%Event{type: type}), do: type in [:telemetry, :log]

  @doc "The number of events that report an error."
  @spec error_count(Recording.t()) :: non_neg_integer()
  def error_count(%Recording{events: events}), do: Enum.count(events, &Event.error?/1)

  @doc "The number of collected events dropped over their limits."
  @spec dropped_count(Recording.t()) :: non_neg_integer()
  def dropped_count(%Recording{dropped: dropped}),
    do: Enum.sum_by(dropped, fn {_name, count} -> count end)

  @doc "Classes for an event's timeline marker. Errors are larger and red."
  @spec marker_class(Event.t()) :: String.t()
  def marker_class(%Event{} = event) do
    if Event.error?(event), do: @error_marker, else: type_marker_class(event.type)
  end

  @typedoc "A piece of an event's row: words in the interface's font, or code in monospace."
  @type part :: {:text, String.t()} | {:code, Phoenix.HTML.safe()}

  @doc """
  An event's row, as words and code: the action in the interface's font,
  and what it acted on in monospace, coloured as Lumis colours code. Logs
  and exit reasons read as text. `label/1` is the same in plain text.
  """
  @spec parts(Event.t()) :: [part()]
  def parts(%Event{type: :mount}), do: [{:text, "mount"}]

  def parts(%Event{type: :event, data: %{name: name, params: params} = data}) do
    target =
      case data do
        %{target: {module, id}} -> [{:text, "→"}, {:code, component_code(module, id)}]
        %{} -> []
      end

    [{:text, name} | target] ++ params_parts(params)
  end

  def parts(%Event{type: :params, data: %{uri: uri}}),
    do: [{:text, "navigate →"}, {:code, escape(uri)}]

  def parts(%Event{type: :info, data: %{tag: nil}}), do: [{:text, "handle_info"}]

  def parts(%Event{type: :info, data: %{tag: tag}}),
    do: [{:text, "handle_info"}, {:code, Highlight.term(tag, limit: 5, printable_limit: 60)}]

  def parts(%Event{type: :render, data: %{assigns: assigns}}),
    do: [{:text, "assigns"}, {:code, names_code(assigns)}]

  def parts(%Event{type: :component, data: %{module: module, id: id, assigns: assigns}}),
    do: [{:code, component_code(module, id)}, {:text, "assigns"}, {:code, names_code(assigns)}]

  def parts(%Event{type: :component_destroyed, data: %{module: module, id: id}}),
    do: [{:code, component_code(module, id)}, {:text, "removed"}]

  def parts(%Event{type: :telemetry, data: %{summary: summary} = data} = event)
      when is_binary(summary) do
    summary =
      case language(data) do
        nil -> {:text, summary}
        language -> {:code, summary |> String.replace(~r/\s+/, " ") |> Highlight.code(language)}
      end

    [summary | error_parts(event)]
  end

  def parts(%Event{type: :viewport, data: %{width: width, height: height} = viewport}),
    do: [
      {:text, "viewport"},
      {:code, token("number", "#{width} × #{height}")},
      {:text, Atom.to_string(Client.orientation(viewport))}
    ]

  def parts(%Event{type: :state, data: %{key: key, changes: changes}}) do
    if key == State.inputs_key(),
      do: [{:text, "input"} | Enum.map(changes, &{:code, input_code(&1)})],
      else: [
        {:code,
         {:safe, safe([token("variable-member", key), token("punctuation-delimiter", ":")])}}
        | Enum.map(Enum.sort(changes), &{:code, field_code(&1)})
      ]
  end

  def parts(%Event{} = event), do: [{:text, Event.label(event)}]

  defp present(details), do: Enum.reject(details, fn {_name, value} -> value == nil end)

  defp duration(nil), do: nil
  defp duration(ms), do: Format.milliseconds(ms)

  defp term(nil), do: nil
  defp term(value), do: Highlight.term(value, pretty: true, limit: 50, printable_limit: 1_000)

  defp metadata(metadata) when metadata == %{}, do: nil
  defp metadata(metadata), do: Highlight.term(metadata, pretty: true, limit: 50)

  defp summary(%{summary: summary} = data) when is_binary(summary) do
    case language(data) do
      nil -> summary
      language -> Highlight.code(summary, language)
    end
  end

  defp summary(%{summary: summary}), do: summary

  # Events recorded before collectors said what language a summary is in
  # have no `:language`; Ecto's are the queries, named `[..., :query]`.
  defp language(%{language: language}), do: language
  defp language(%{event: event}) when is_list(event), do: if(query?(event), do: :sql)
  defp language(_data), do: nil

  defp query?([:query]), do: true
  defp query?([_name | rest]), do: query?(rest)
  defp query?([]), do: false

  defp type_marker_class(:mount), do: "size-1.5 bg-ink"
  defp type_marker_class(:event), do: "size-1.5 bg-kind-event"
  defp type_marker_class(:params), do: "size-1.5 bg-kind-nav"
  defp type_marker_class(:info), do: "size-1 bg-kind-log"
  defp type_marker_class(:render), do: "size-1 bg-kind-render"
  defp type_marker_class(:component), do: "size-1 bg-kind-component"
  defp type_marker_class(:component_destroyed), do: "size-1 bg-kind-component"
  defp type_marker_class(:telemetry), do: "size-1 bg-kind-query"
  defp type_marker_class(:log), do: "size-1 bg-kind-log"
  defp type_marker_class(:exit), do: @error_marker
  defp type_marker_class(:viewport), do: "size-1 bg-kind-render"
  defp type_marker_class(:state), do: "size-1 bg-kind-component"

  defp visible?(event, filters) do
    not MapSet.member?(filters.hidden, kind(event.type)) and matches?(event, filters.query) and
      (not filters.errors_only or Event.error?(event))
  end

  defp error_parts(%Event{data: %{error: error}}) when is_binary(error),
    do: [{:text, "— " <> error}]

  defp error_parts(%Event{}), do: []

  defp params_parts(params) do
    case Label.params(params) do
      [] ->
        []

      pairs ->
        code =
          pairs
          |> Enum.map(fn {key, value} ->
            [token("variable-member", key), "=", token("string", String.slice(value, 0, 40))]
          end)
          |> Enum.intersperse(token("punctuation-delimiter", ", "))

        [{:code, {:safe, safe(code)}}]
    end
  end

  defp names_code(assigns) do
    names =
      assigns
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(&token("string-special-symbol", to_string(&1)))
      |> Enum.intersperse(token("punctuation-delimiter", ", "))

    {:safe, safe(names)}
  end

  defp component_code(module, id) do
    id = if is_binary(id), do: id, else: inspect(id)

    {:safe,
     safe([
       token("module", inspect(module)),
       token("punctuation-special", "#"),
       token("string", id)
     ])}
  end

  defp input_code({selector, %{} = fields}) do
    values =
      Enum.map(fields, fn {_name, value} ->
        Highlight.term(value, limit: 5, printable_limit: 40)
      end)

    {:safe, safe([token("variable-member", selector), " " | Enum.intersperse(values, ", ")])}
  end

  defp input_code({selector, _filtered}), do: token("variable-member", selector)

  defp field_code({field, value}),
    do: {:safe, safe([escape(field), " ", Highlight.term(value, limit: 5, printable_limit: 40)])}

  # A span with one of Lumis's classes, for code built here rather than parsed.
  defp token(class, text),
    do: {:safe, ["<span class=\"l-", class, "\">", safe(escape(text)), "</span>"]}

  defp escape(text), do: Phoenix.HTML.html_escape(text)

  defp safe(list) when is_list(list), do: Enum.map(list, &safe/1)
  defp safe({:safe, data}), do: data
  defp safe(text) when is_binary(text), do: text
end
