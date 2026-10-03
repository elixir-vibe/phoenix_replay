defmodule PhoenixReplay.RecorderTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Recording, Storage}
  alias PhoenixReplay.Recorder.Buffer
  alias PhoenixReplay.Recording.{Event, Timeline}
  alias PhoenixReplay.Test.{Assertions, Fixtures}

  @endpoint PhoenixReplay.Test.Endpoint

  setup do
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
  end

  defp recording_id(view), do: :sys.get_state(view.pid).socket.private.phoenix_replay.id

  test "records events and render diffs without touching the view's assigns" do
    {:ok, view, _html} = live(build_conn(), "/counter")
    id = recording_id(view)

    render_click(view, "inc")
    render_click(view, "inc")
    render_click(view, "dec")
    send(view.pid, :reset)
    render(view)

    refute Enum.any?(
             Map.keys(:sys.get_state(view.pid).socket.assigns),
             &(to_string(&1) =~ "replay")
           )

    assert {:ok, %Recording{view: PhoenixReplay.Test.Live.Counter} = recording} = Buffer.fetch(id)
    assert recording.url == "http://www.example.com/counter"

    assert [
             :mount,
             :params,
             :render,
             :event,
             :render,
             :event,
             :render,
             :event,
             :render,
             :info,
             :render
           ] =
             Enum.map(recording.events, & &1.type)

    assert [0, 1, 2, 1, 0] =
             for(
               %Event{type: :render, data: %{assigns: %{count: count}}} <- recording.events,
               do: count
             )

    assert %Event{data: %{tag: :reset}} = Enum.find(recording.events, &(&1.type == :info))

    assert recording.events
           |> Enum.map(& &1.at)
           |> Enum.chunk_every(2, 1, :discard)
           |> Enum.all?(fn [a, b] -> a <= b end)
  end

  test "saves the recording when the view exits" do
    {:ok, view, _html} = live(build_conn(), "/counter")
    id = recording_id(view)
    render_click(view, "inc")
    GenServer.stop(view.pid)

    recording = Assertions.eventually(fn -> Storage.fetch(Fixtures.storage(), id) end)
    assert Timeline.assigns_at(recording, Timeline.last_index(recording)).count == 1
    # The buffer closes once the save task reports back, just after storage has it.
    Assertions.eventually(fn -> if Buffer.fetch(id) == :error, do: {:ok, :closed} end)
  end

  test "sanitizes params and assigns" do
    {:ok, view, _html} = live(build_conn(), "/form")
    id = recording_id(view)
    render_change(view, "validate", %{"name" => "dan", "password" => "hunter2"})

    {:ok, recording} = Buffer.fetch(id)
    refute inspect(recording) =~ "hunter2"

    assert %{name: "dan", password: "[FILTERED]"} =
             Timeline.assigns_at(recording, Timeline.last_index(recording))
  end

  test "stops recording after max_events" do
    Application.put_env(:phoenix_replay, :max_events, 3)
    on_exit(fn -> Application.delete_env(:phoenix_replay, :max_events) end)

    {:ok, view, _html} = live(build_conn(), "/counter")
    for _ <- 1..5, do: render_click(view, "inc")

    assert {:ok, %{events: events}} = Buffer.fetch(recording_id(view))
    assert length(events) == 3
  end
end
