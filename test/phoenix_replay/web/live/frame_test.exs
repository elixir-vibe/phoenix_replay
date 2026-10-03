defmodule PhoenixReplay.Web.Live.FrameTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Storage
  alias PhoenixReplay.Test.Fixtures
  alias PhoenixReplay.Web.Playback

  @endpoint PhoenixReplay.Test.Endpoint

  setup do
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
  end

  defp save(recording) do
    Storage.save(Fixtures.storage(), recording)
    recording
  end

  defp seek(channel, index) do
    Playback.seek(channel, index)
  end

  test "renders the recorded view at each position" do
    save(Fixtures.counter_recording(id: "frame", clicks: 2))
    {:ok, view, html} = live(build_conn(), "/replay/frame/frame?channel=c1")

    assert html =~ ~s(<span id="count">0</span>)
    seek("c1", 5)
    assert render(view) =~ ~s(<span id="count">2</span>)
    seek("c1", 3)
    assert render(view) =~ ~s(<span id="count">1</span>)

    assert view |> element("button", "+") |> render_click() =~ ~s(<span id="count">1</span>)
  end

  test "loads the host stylesheet and the dashboard bundle" do
    save(Fixtures.counter_recording(id: "frame"))
    html = build_conn() |> get("/replay/frame/frame") |> html_response(200)

    assert html =~ ~s(href="/assets/css/app.css")
    assert html =~ ~r|src="/replay/assets/phoenix_live_view-[0-9.]+\.js"|
    assert html =~ ~r|src="/replay/assets/dashboard-[0-9a-f]{8}\.js"|
  end

  test "replays flash messages and clears assigns missing later" do
    recording =
      save(%{
        Fixtures.counter_recording(id: "flash", clicks: 0)
        | events: [
            %Event{
              at: 0,
              type: :render,
              data: %{assigns: %{count: 1, flash: %{"info" => "Saved"}}}
            },
            %Event{at: 1, type: :mount, data: %{assigns: %{count: 2}}}
          ]
      })

    {:ok, view, html} = live(build_conn(), "/replay/#{recording.id}/frame?channel=c2")
    assert html =~ "Saved"

    seek("c2", 1)
    refute render(view) =~ "Saved"
  end

  test "shows a placeholder when the template cannot render" do
    save(%{
      Fixtures.counter_recording(id: "broken")
      | view: PhoenixReplay.Test.Live.Form,
        events: [
          %Event{at: 0, type: :render, data: %{assigns: %{name: "ok", password: ""}}},
          %Event{at: 1, type: :render, data: %{assigns: %{name: nil}}}
        ]
    })

    {:ok, view, html} = live(build_conn(), "/replay/broken/frame?channel=c3")
    assert html =~ "Hello OK"

    seek("c3", 1)
    html = render(view)
    assert html =~ "Could not render PhoenixReplay.Test.Live.Form"
    assert Process.alive?(view.pid)

    seek("c3", 0)
    assert render(view) =~ "Hello OK"
  end

  test "responds 404 for unauthorized recordings" do
    save(Fixtures.counter_recording(id: "secret-1"))

    assert_raise PhoenixReplay.Web.NotFoundError, fn ->
      live(build_conn(), "/restricted/replay/secret-1/frame")
    end
  end
end
