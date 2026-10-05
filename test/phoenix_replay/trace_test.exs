defmodule PhoenixReplay.TraceTest do
  use ExUnit.Case, async: false

  alias PhoenixReplay.{Storage, Trace}
  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Test.Fixtures

  setup do
    recording = Fixtures.counter_recording(id: "traced")
    failing = %{Fixtures.counter_recording(id: "failing") | view: PhoenixReplay.Test.Live.Form}
    error = %Event{at: 1_500, type: :log, data: %{level: :error, message: "boom", metadata: %{}}}
    failing = %{failing | events: List.insert_at(failing.events, 4, error)}

    for saved <- [recording, failing], do: :ok = Storage.save(Fixtures.storage(), saved)
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
    %{recording: recording}
  end

  # Other tests' sessions can end into the same storage, so only these
  # two recordings are looked at.
  defp ids(filters),
    do: filters |> Trace.find() |> Enum.map(& &1.id) |> Enum.filter(&(&1 in ~w(traced failing)))

  test "finds recordings by view, error and text" do
    assert ids(errors: true) == ["failing"]
    assert ids(view: PhoenixReplay.Test.Live.Form) == ["failing"]
    assert ids(view: "PhoenixReplay.Test.Live.Counter") == ["traced"]
    assert ids(text: "trac") == ["traced"]
    assert [_one] = Trace.find(limit: 1)
    # Saved recordings are not running sessions.
    assert Trace.find(live: true) == []

    assert_raise ArgumentError, ~r/unknown keys \[:typo\]/, fn -> Trace.find(typo: 1) end
  end

  test "lists events with the player's indexes, grouped under what caused them",
       %{recording: recording} do
    events = Trace.events(recording)

    assert Enum.map(events, &{&1.index, &1.type, &1.caused_by}) == [
             {0, :mount, nil},
             {1, :render, 0},
             {2, :event, nil},
             {3, :render, 2},
             {4, :event, nil},
             {5, :render, 4}
           ]

    assert %{label: "inc", at: 1_000, error?: false, data: %{name: "inc"}} = Enum.at(events, 2)
    # An id reads the recording first.
    assert Trace.events("traced") == events

    assert [%{label: "[error] boom", error?: true, caused_by: 2}] =
             "failing" |> Trace.events() |> Enum.filter(& &1.error?)
  end

  test "shows the view at a moment and what the event changed" do
    assert %{
             index: 3,
             at: 1_001,
             event: %{type: :render},
             url: "http://localhost/counter",
             assigns: %{count: 1},
             client_state: %{},
             changed: [%{path: "count", change: :changed, before: 0, after: 1}]
           } = Trace.state("traced", 3)

    refute Map.has_key?(Trace.state("traced", 3).assigns, :phoenix_replay_state)
    # Events that set no assigns change nothing.
    assert %{changed: [], assigns: %{count: 1}} = Trace.state("traced", 4)
  end

  test "says which recording it cannot find" do
    assert Trace.fetch("missing") == {:error, :not_found}
    assert_raise ArgumentError, ~s(no recording "missing"), fn -> Trace.events("missing") end
  end
end
