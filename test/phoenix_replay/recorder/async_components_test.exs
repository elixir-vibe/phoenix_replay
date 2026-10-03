defmodule PhoenixReplay.Recorder.AsyncComponentsTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.Recorder.Buffer
  alias PhoenixReplay.Recording.Timeline
  alias PhoenixReplay.Storage
  alias PhoenixReplay.Test.{Fixtures, Sessions, Tasks}
  alias PhoenixReplay.Test.Live.AsyncPrice

  @endpoint PhoenixReplay.Test.Endpoint

  setup context do
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
    Sessions.setup_sessions(context)
  end

  defp component_state(id) do
    {:ok, recording} = Buffer.fetch(id)
    Timeline.components_at(recording, Timeline.last_index(recording))[{AsyncPrice, "price"}]
  end

  test "records component state applied by async results", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/async")
    assert render_async(view) =~ ~s(<span class="total">100</span>)
    Tasks.await()

    assert %{price: %Phoenix.LiveView.AsyncResult{ok?: true, result: 42}, total: 100} =
             component_state(id)
  end

  test "does not snapshot renders caused by recorded events", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/async")
    render_async(view)
    Tasks.await()

    view |> element("button") |> render_click()
    Tasks.await()

    {:ok, %{events: events}} = Buffer.fetch(id)
    after_click = Enum.drop_while(events, &(&1.type != :event))

    assert [%{type: :event}, %{type: :component, data: %{assigns: %{clicks: 1} = changes}}] =
             after_click

    refute Map.has_key?(changes, :price)
  end

  test "replays state applied by async results", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/async")
    render_async(view)
    Tasks.await()
    view |> element("button") |> render_click()
    assert Sessions.stop(sessions, view) == :persisted

    {:ok, recording} = Storage.fetch(Fixtures.storage(), id)
    {:ok, frame, _html} = live(build_conn(), "/replay/#{id}/frame?channel=async")
    PhoenixReplay.Web.Playback.seek("async", Timeline.last_index(recording))
    :sys.get_state(frame.pid)

    html = render(frame)
    assert html =~ ~s(<span class="price">42</span>)
    assert html =~ ~s(<span class="total">100</span>)
  end
end
