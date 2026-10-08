defmodule PhoenixReplay.Web.Live.FrameTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.Recording.Event
  alias PhoenixReplay.Storage
  alias PhoenixReplay.Test.{Fixtures, Sessions}
  alias PhoenixReplay.Web.Player.Channel

  @endpoint PhoenixReplay.Test.Endpoint

  setup context do
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
    Sessions.setup_sessions(context)
  end

  defp save(recording) do
    Storage.save(Fixtures.storage(), recording)
    recording
  end

  defp seek(channel, index) do
    Channel.seek(channel, index)
  end

  test "replays client state through replay_render/1, back and forth" do
    save(%PhoenixReplay.Recording{
      id: "client",
      view: PhoenixReplay.Test.Live.ClientSearch,
      connected_at: 0,
      events: [
        %Event{at: 0, type: :mount, data: %{assigns: %{}}},
        # The live view renders without a query: the browser holds it.
        %Event{at: 5, type: :render, data: %{assigns: %{title: "Shop", query: nil}}},
        %Event{
          at: 300,
          type: :state,
          data: %{
            span: 200,
            entries: [[0, "search", %{"query" => "sh"}], [200, "search", %{"page" => 2}]]
          }
        },
        %Event{
          at: 400,
          type: :state,
          data: %{span: 0, entries: [[0, "search", %{"query" => "shoes"}]]}
        }
      ]
    })

    {:ok, view, html} = live(build_conn(), "/replay/client/frame?channel=c-state")
    assert html =~ "<h1>Shop</h1>"
    refute html =~ "value="

    # The entries land at 100, 300 and 400 ms: indexes 2, 3 and 4.
    seek("c-state", 2)
    assert render(view) =~ ~s(value="sh")
    refute render(view) =~ ~s(<span id="page">2</span>)

    seek("c-state", 4)
    html = render(view)
    assert html =~ ~s(value="shoes")
    assert html =~ ~s(<span id="page">2</span>)

    seek("c-state", 1)
    refute render(view) =~ "value="
  end

  test "hands the frame's script the form values recorded up to each position" do
    inputs = PhoenixReplay.Recording.State.inputs_key()

    recording = Fixtures.counter_recording(id: "typed", clicks: 1)

    typed = %Event{
      at: 3_000,
      type: :state,
      data: %{span: 0, entries: [[0, inputs, %{"#q" => %{"q" => "shoes"}}]]}
    }

    # The replay places state by its time, after the click at 1 s.
    save(%{recording | events: [typed | recording.events]})

    # Before anything was typed there is nothing to put back.
    {:ok, view, _html} = live(build_conn(), "/replay/typed/frame?channel=c-inputs")
    refute_push_event(view, "phx_replay:inputs", %{})

    seek("c-inputs", 4)
    render(view)
    assert_push_event(view, "phx_replay:inputs", %{values: %{"#q" => %{"q" => "shoes"}}})

    # Nothing new to put back: the frame's script is not told again.
    seek("c-inputs", 4)
    render(view)
    refute_push_event(view, "phx_replay:inputs", %{})

    seek("c-inputs", 1)
    render(view)
    assert_push_event(view, "phx_replay:inputs", %{values: values})
    assert values == %{}
  end

  defmodule Replay do
    @moduledoc false
    @behaviour PhoenixReplay.Replay

    @impl true
    def root_attributes(_view, assigns),
      do: %{"data-count" => assigns[:count], "data-none" => nil}
  end

  defp replay_with(module) do
    Application.put_env(:phoenix_replay, :replay, module)
    on_exit(fn -> Application.delete_env(:phoenix_replay, :replay) end)
  end

  test "migrates an older recording's assigns with the app's migrations" do
    # See PhoenixReplay.Test.ReplayMigrations.ClicksToCount.
    save(%PhoenixReplay.Recording{
      id: "renamed",
      view: PhoenixReplay.Test.Live.Counter,
      connected_at: System.system_time(:millisecond),
      events: [
        %Event{at: 0, type: :mount, data: %{assigns: %{}}},
        %Event{at: 5, type: :render, data: %{assigns: %{clicks: 7}}}
      ]
    })

    {:ok, view, _html} = live(build_conn(), "/replay/renamed/frame?channel=c-renamed")
    assert render(view) =~ ~s(<span id="count">7</span>)

    # Made after the migration, a recording is left as it is.
    save(%PhoenixReplay.Recording{
      id: "current",
      view: PhoenixReplay.Test.Live.Counter,
      connected_at: System.system_time(:millisecond),
      code: %{release: nil, modules: %{}, deps: %{}, migration: 20_261_007_120_000},
      events: [
        %Event{at: 0, type: :mount, data: %{assigns: %{}}},
        %Event{at: 5, type: :render, data: %{assigns: %{clicks: 7}}}
      ]
    })

    {:ok, view, _html} = live(build_conn(), "/replay/current/frame?channel=c-current")
    assert render(view) =~ ~s(<span id="count"></span>)
  end

  test "sends the app's root layout rendered with each moment's assigns, when it changes" do
    recording = save(Fixtures.counter_recording(id: "rooted", clicks: 1))

    {:ok, view, _html} = live(build_conn(), "/app/replay/rooted/frame?channel=c-root")
    assert_push_event(view, "phx_replay:root", %{layout: layout, attributes: %{}})
    assert layout =~ ~s(<html lang="en" data-count="0">)

    last = length(recording.events) - 1
    seek("c-root", last)
    render(view)
    assert_push_event(view, "phx_replay:root", %{layout: layout})
    assert layout =~ ~s(data-count="1")

    # Unchanged, the frame's script is not told again.
    seek("c-root", last)
    render(view)
    refute_push_event(view, "phx_replay:root", %{})
  end

  test "sends nothing for the dashboard's own layout, but the app's root attributes" do
    {:ok, view, _html} =
      live(build_conn(), "/replay/#{save(Fixtures.counter_recording(id: "plain")).id}/frame")

    refute_push_event(view, "phx_replay:root", %{})

    replay_with(Replay)
    {:ok, view, _html} = live(build_conn(), "/replay/plain/frame?channel=c-plain")

    assert_push_event(view, "phx_replay:root", %{
      layout: nil,
      attributes: %{"data-count" => "0", "data-none" => nil}
    })
  end

  test "renders an assign the recording lacks as nil, and tells the player" do
    # As a session recorded before the template began to read @count.
    save(%PhoenixReplay.Recording{
      id: "older",
      view: PhoenixReplay.Test.Live.Counter,
      connected_at: System.system_time(:millisecond),
      events: [
        %Event{at: 0, type: :mount, data: %{assigns: %{}}},
        %Event{at: 5, type: :render, data: %{assigns: %{other: 1}}}
      ]
    })

    :ok = Channel.subscribe("c-older")
    {:ok, view, _html} = live(build_conn(), "/replay/older/frame?channel=c-older")

    assert_receive {Channel, {:unrecorded, [:count]}}
    html = render(view)
    refute html =~ "Could not render"
    assert html =~ ~s(<span id="count"></span>)

    # Moving on, it stays unrecorded: the player is not told otherwise.
    seek("c-older", 1)
    render(view)
    refute_receive {Channel, {:unrecorded, _keys}}
  end

  test "tells an export's stage when each position has rendered" do
    save(Fixtures.counter_recording(id: "staged", clicks: 1))

    {:ok, view, _html} = live(build_conn(), "/replay/staged/frame?channel=c-stage&stage=1")
    assert_push_event(view, "phx_replay:shown", %{index: 1})

    seek("c-stage", 3)
    render(view)
    assert_push_event(view, "phx_replay:shown", %{index: 3})

    # The player's frame is not told.
    {:ok, view, _html} = live(build_conn(), "/replay/staged/frame?channel=c-player")
    seek("c-player", 3)
    render(view)
    refute_push_event(view, "phx_replay:shown", %{})
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

  test "replays LiveComponent state", %{sessions: sessions} do
    {:ok, cart, _html, id} = Sessions.live(sessions, build_conn(), "/cart")
    for _ <- 1..3, do: cart |> element("#item-pear button") |> render_click()
    assert Sessions.stop(sessions, cart) == :persisted
    {:ok, recording} = Storage.fetch(Fixtures.storage(), id)

    quantities = fn html ->
      for item <- ~w(apple pear), into: %{} do
        [quantity] =
          html
          |> LazyHTML.from_fragment()
          |> LazyHTML.query("#item-#{item} .quantity")
          |> LazyHTML.text()
          |> List.wrap()

        {item, quantity}
      end
    end

    last = length(recording.events) - 1
    {:ok, view, _html} = live(build_conn(), "/replay/#{id}/frame?channel=c4")
    # The frame refreshes components with send_update/3, which it processes
    # after the seek; reading its state waits for that.
    replay_at = fn index ->
      seek("c4", index)
      :sys.get_state(view.pid)
      quantities.(render(view))
    end

    assert replay_at.(last) == %{"apple" => "0", "pear" => "3"}

    after_one_click =
      Enum.find_index(
        recording.events,
        &match?(%{type: :component, data: %{assigns: %{quantity: 1}}}, &1)
      )

    assert replay_at.(after_one_click) == %{"apple" => "0", "pear" => "1"}

    assert view |> element("#item-pear button") |> render_click() =~ "pear"
    assert quantities.(render(view)) == %{"apple" => "0", "pear" => "1"}
  end

  test "waits for a live session from the player instead of reading the buffer" do
    recording = Fixtures.counter_recording(id: "live-frame", clicks: 1)
    :ok = PhoenixReplay.Session.Buffer.open(recording, self(), PhoenixReplay.Config.load())
    on_exit(fn -> PhoenixReplay.Session.Buffer.close("live-frame") end)

    {:ok, view, html} = live(build_conn(), "/replay/live-frame/frame?channel=c9")
    assert html =~ "Redacting the session"

    seek("c9", 3)
    assert render(view) =~ "Redacting the session"

    Channel.load("c9", recording)
    assert render(view) =~ ~s(<span id="count">0</span>)
    seek("c9", 3)
    assert render(view) =~ ~s(<span id="count">1</span>)
  end

  test "responds 404 for unauthorized recordings" do
    save(Fixtures.counter_recording(id: "secret-1"))

    assert_raise PhoenixReplay.Web.NotFoundError, fn ->
      live(build_conn(), "/restricted/replay/secret-1/frame")
    end
  end
end
