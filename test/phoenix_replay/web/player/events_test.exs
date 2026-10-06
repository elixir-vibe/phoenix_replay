defmodule PhoenixReplay.Web.Player.EventsTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Recording
  alias PhoenixReplay.Recording.{Event, Timeline}
  alias PhoenixReplay.Web.Player.Events

  test "labels events" do
    event = fn type, data -> Event.label(%Event{at: 0, type: type, data: data}) end

    assert event.(:event, %{name: "save", params: %{}}) == "save"

    assert event.(:event, %{
             name: "validate",
             params: %{"_target" => ["user"], "user" => %{"name" => "Dan"}}
           }) ==
             "validate: name=Dan"

    assert event.(:event, %{name: "add", params: %{}, target: {MyApp.Item, "pear"}}) ==
             "add → MyApp.Item#pear"

    assert event.(:params, %{params: %{}, uri: "/a"}) == "navigate → /a"
    assert event.(:info, %{tag: :tick}) == "handle_info :tick"
    assert event.(:info, %{tag: nil}) == "handle_info"
    assert event.(:render, %{assigns: %{b: 1, a: 2}}) == "assigns a, b"

    query = %{event: [:repo, :query], summary: "SELECT 1", measurements: %{}, metadata: %{}}
    assert event.(:telemetry, Map.put(query, :error, nil)) == "SELECT 1"
    assert event.(:telemetry, %{query | summary: nil} |> Map.put(:error, nil)) == "repo.query"
    assert event.(:telemetry, Map.put(query, :error, "timeout")) == "SELECT 1 — timeout"
    assert event.(:log, %{level: :warning, message: "slow", metadata: %{}}) == "[warning] slow"

    assert event.(:exit, %{reason: "** (RuntimeError) boom\n    stack"}) ==
             "exited: ** (RuntimeError) boom"
  end

  test "groups events into kinds, LiveView first" do
    recording = %Recording{
      id: "r",
      view: View,
      connected_at: 0,
      events: [
        %Event{at: 0, type: :log, data: %{level: :error, message: "", metadata: %{}}},
        %Event{at: 1, type: :mount},
        %Event{at: 2, type: :render, data: %{assigns: %{}}}
      ],
      dropped: %{"repo.query" => 3}
    }

    assert Events.kinds(recording) == [:liveview, :logs]
    assert Events.error_count(recording) == 1
    assert Events.dropped_count(recording) == 3
    assert Events.collected?(hd(recording.events))
  end

  test "marks errors" do
    error = %Event{at: 0, type: :log, data: %{level: :error, message: "", metadata: %{}}}
    assert Events.marker_class(error) == "size-2.5 bg-error ring-3 ring-error-soft"
    assert Events.marker_class(%Event{at: 0, type: :params}) == "size-1.5 bg-kind-nav"
  end

  defp event(at, type, data), do: %Event{at: at, type: type, data: data}

  test "groups events into interactions led by mounts, events, navigation and messages" do
    events = [
      mount = event(0, :mount, %{assigns: %{}}),
      render = event(1, :render, %{assigns: %{a: 1}}),
      click = event(2, :event, %{name: "save", params: %{}}),
      query = event(3, :telemetry, %{event: [:repo, :query], summary: "SELECT 1", error: nil}),
      info = event(4, :info, %{tag: :tick})
    ]

    assert Timeline.interactions(events) == [
             {{mount, 0}, [{render, 1}]},
             {{click, 2}, [{query, 3}]},
             {{info, 4}, []}
           ]

    # Events before the first leader start a group of their own.
    assert Timeline.interactions([render, click]) == [{{render, 0}, []}, {{click, 1}, []}]
    assert Timeline.interactions([]) == []
  end

  test "describes kinds, lanes, the first error and what an event changed" do
    log = event(2, :log, %{level: :error, message: "boom", metadata: %{}})

    recording = %Recording{
      id: "r",
      view: View,
      connected_at: 0,
      events: [
        event(0, :mount, %{assigns: %{a: 1, b: 2}}),
        event(1, :render, %{assigns: %{b: 3}}),
        log
      ]
    }

    assert Events.kind_counts(recording) == %{liveview: 2, logs: 1}
    assert [{:liveview, [_mount, _render]}, {:logs, [{^log, 2}]}] = Events.lanes(recording)
    assert Events.first_error_index(recording) == 2
    assert Events.first_error_index(%{recording | events: []}) == nil
    assert Event.changed_keys(Enum.at(recording.events, 1)) == [:b]
    assert Event.changed_keys(log) == []
    assert Event.changed_keys(nil) == []
    assert Events.kind_class(:logs) == "bg-kind-log"
  end

  test "reads only known kinds sent by the browser" do
    assert Events.parse_kind("logs") == {:ok, :logs}
    assert Events.parse_kind("nope") == :error
  end

  test "matches labels and describes collected events" do
    log = event(0, :log, %{level: :error, message: "Sync failed", metadata: %{}})
    assert Events.matches?(log, "")
    assert Events.matches?(log, "sync FAILED")
    refute Events.matches?(log, "select")
    assert Events.details(log) == [{"Level", "error"}, {"Message", "Sync failed"}]

    query =
      event(1, :telemetry, %{
        event: [:repo, :query],
        summary: "SELECT 1",
        language: nil,
        measurements: %{duration: 1.5},
        metadata: %{},
        error: "timeout"
      })

    assert Events.details(query) == [
             {"Event", "repo.query"},
             {"Summary", "SELECT 1"},
             {"Duration", "1.50 ms"},
             {"Error", "timeout"}
           ]

    assert Events.details(event(2, :exit, %{reason: "boom"})) == [{"Reason", "boom"}]
  end

  test "describes every kind of event for the details pane" do
    # Values as their text, without the highlighting.
    text = fn event ->
      Enum.map(Events.details(event), fn
        {name, value} when is_binary(value) ->
          {name, value}

        {name, safe} ->
          html = Phoenix.HTML.safe_to_string(safe)
          {name, html |> LazyHTML.from_fragment() |> LazyHTML.text()}
      end)
    end

    assert text.(event(0, :mount, %{assigns: %{count: 0}})) == [{"Assigns", "%{count: 0}"}]

    assert text.(event(0, :event, %{name: "save", params: %{"id" => "7"}, target: {Cart, 3}})) ==
             [{"Event", "save"}, {"Component", "Cart#3"}, {"Params", ~s(%{"id" => "7"})}]

    assert text.(event(0, :params, %{uri: "http://x/a?q=1", params: %{"q" => "1"}})) ==
             [{"URL", "http://x/a?q=1"}, {"Params", ~s(%{"q" => "1"})}]

    assert text.(event(0, :info, %{tag: :tick})) == [{"Message tag", ":tick"}]
    assert [{"Message", _untagged}] = text.(event(0, :info, %{tag: nil}))
    assert text.(event(0, :render, %{assigns: %{count: 1}})) == [{"Assigns", "%{count: 1}"}]

    assert text.(event(0, :component, %{module: Cart, id: "c", assigns: %{n: 1}})) ==
             [{"Component", "Cart#c"}, {"Assigns", "%{n: 1}"}]

    assert text.(event(0, :component_destroyed, %{module: Cart, id: "c"})) ==
             [{"Component", "Cart#c"}]

    assert text.(event(0, :viewport, %{width: 844, height: 390, dpr: 3})) ==
             [{"Size", "844 × 390"}, {"Orientation", "landscape"}, {"Pixel ratio", "3"}]

    assert text.(event(0, :state, %{key: "search", changes: %{"query" => "milk"}})) ==
             [{"Key", "search"}, {"Changes", ~s(%{"query" => "milk"})}]

    inputs = PhoenixReplay.Recording.State.inputs_key()

    assert [{"Form controls", _values}] =
             text.(event(0, :state, %{key: inputs, changes: %{"#q" => %{"q" => "x"}}}))
  end

  test "highlights what a collector said is code, and only that" do
    sql =
      event(1, :telemetry, %{
        event: [:repo, :query],
        summary: "SELECT id\n  FROM users",
        language: :sql,
        measurements: %{},
        metadata: %{source: "users"},
        error: nil
      })

    html = fn safe -> Phoenix.HTML.safe_to_string(safe) end
    details = Map.new(Events.details(sql))

    assert html.(details["Summary"]) =~ ~s(<span class="l-keyword">SELECT</span>)
    assert html.(details["Metadata"]) =~ ~s(<span class="l-string">&quot;users&quot;</span>)

    # One line in the event list.
    assert [{:code, row}] = Events.parts(sql)
    assert html.(row) =~ ~r/id<\/span> <span class="l-keyword">FROM/

    assert [{:text, "SELECT id\n  FROM users"}] =
             Events.parts(%{sql | data: %{sql.data | language: nil}})

    # Recorded before collectors named a language: Ecto's queries still are SQL.
    legacy = %{sql | data: Map.delete(sql.data, :language)}
    assert [{:code, legacy_row}] = Events.parts(legacy)
    assert html.(legacy_row) =~ "l-keyword"
  end

  test "splits rows into the action and the code it acted on" do
    text = fn parts ->
      Enum.map(parts, fn
        {:text, text} ->
          {:text, text}

        {:code, safe} ->
          {:code, safe |> Phoenix.HTML.safe_to_string() |> String.replace(~r/<[^>]+>/, "")}
      end)
    end

    assert text.(
             Events.parts(
               event(0, :event, %{name: "toggle", params: %{"id" => "7", "_target" => "x"}})
             )
           ) ==
             [{:text, "toggle"}, {:code, "id=7"}]

    assert text.(Events.parts(event(0, :info, %{tag: :task_updated}))) ==
             [{:text, "handle_info"}, {:code, ":task_updated"}]

    assert text.(Events.parts(event(0, :render, %{assigns: %{tasks: [], filter: "all"}}))) ==
             [{:text, "assigns"}, {:code, "filter, tasks"}]

    assert text.(Events.parts(event(0, :params, %{params: %{}, uri: "http://x/<b>"}))) ==
             [{:text, "navigate →"}, {:code, "http://x/&lt;b&gt;"}]

    # Prose stays prose.
    assert Events.parts(event(0, :log, %{level: :info, message: "Saved", metadata: %{}})) ==
             [{:text, "[info] Saved"}]
  end
end
