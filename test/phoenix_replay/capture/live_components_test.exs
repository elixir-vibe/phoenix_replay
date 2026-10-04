defmodule PhoenixReplay.Capture.LiveComponentsTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Recording.{Event, Timeline}
  alias PhoenixReplay.Storage
  alias PhoenixReplay.Test.{Fixtures, Sessions}
  alias PhoenixReplay.Test.Live.CartItem

  @endpoint PhoenixReplay.Test.Endpoint

  setup context do
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
    Sessions.setup_sessions(context)
  end

  defp recording(id) do
    {:ok, recording} = Buffer.fetch(id)
    recording
  end

  test "records component state changed by updates and events", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/cart")
    view |> element("#item-pear button") |> render_click()
    view |> element("#item-pear button") |> render_click()

    recording = recording(id)

    assert %Event{data: %{module: CartItem, id: "apple", assigns: %{name: "apple", quantity: 0}}} =
             Enum.find(
               recording.events,
               &match?(%Event{type: :component, data: %{id: "apple"}}, &1)
             )

    assert %{{CartItem, "apple"} => %{quantity: 0}, {CartItem, "pear"} => %{quantity: 2}} =
             Timeline.components_at(recording, Timeline.last_index(recording))

    refute recording.events
           |> Enum.filter(&(&1.type == :component))
           |> Enum.any?(&Map.has_key?(&1.data.assigns, :myself))
  end

  test "records events handled by components, so the session is kept", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/cart")
    view |> element("#item-pear button") |> render_click()

    assert %Event{type: :event, data: %{name: "add", target: {CartItem, "pear"}}} =
             Enum.find(recording(id).events, &(&1.type == :event))

    assert Sessions.stop(sessions, view) == :persisted
  end

  test "records removed components", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/cart")
    test = self()
    handler = {__MODULE__, :destroyed}

    :telemetry.attach(
      handler,
      [:phoenix, :live_component, :destroyed],
      fn _event, _measures, %{socket: socket}, nil ->
        send(test, {:destroyed, socket.assigns.id})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    render_click(view, "remove", %{"item" => "apple"})

    # Components are destroyed after the client acknowledges their removal.
    # All handlers of one telemetry event run in the view before it handles
    # the next message, so reading its state orders this test after them.
    assert_receive {:destroyed, "apple"}
    :sys.get_state(view.pid)

    recording = recording(id)

    assert %Event{data: %{module: CartItem, id: "apple"}} =
             Enum.find(recording.events, &(&1.type == :component_destroyed))

    assert Map.keys(Timeline.components_at(recording, Timeline.last_index(recording))) ==
             [{CartItem, "pear"}]
  end

  test "stays attached when metadata has an unexpected shape" do
    :telemetry.execute([:phoenix, :live_component, :update, :stop], %{}, %{component: CartItem})
    :telemetry.execute([:phoenix, :live_component, :destroyed], %{}, %{socket: nil})

    handlers = :telemetry.list_handlers([:phoenix, :live_component])
    assert Enum.any?(handlers, &(&1.id == PhoenixReplay.Capture.LiveComponents))
  end

  test "ignores components of views that are not recorded" do
    {:ok, view, _html} = live(build_conn(), "/replay")
    assert Buffer.session(view.pid) == :error
  end

  test "records viewport changes sent with component events", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/cart")
    viewport = %{"width" => 1024, "height" => 768, "dpr" => 2}

    view |> element("#item-pear button") |> render_click(%{"_replay" => viewport})

    recording = recording(id)
    assert %Event{data: %{width: 1024}} = Enum.find(recording.events, &(&1.type == :viewport))

    assert %Event{data: %{params: params}} =
             Enum.find(recording.events, &match?(%Event{type: :event, data: %{target: _}}, &1))

    refute Map.has_key?(params, "_replay")
  end
end
