defmodule PhoenixReplay.RecorderTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Recorder, Recording, Storage}
  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Recording.{Event, Timeline}
  alias PhoenixReplay.Test.{Fixtures, Sessions}

  @endpoint PhoenixReplay.Test.Endpoint

  setup :setup_sessions

  setup do
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
  end

  defp setup_sessions(context), do: Sessions.setup_sessions(context)

  test "records events and render diffs without touching the view's assigns", %{
    sessions: sessions
  } do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/counter")

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

  test "records the layout the view rendered in, as mount settled it", %{sessions: sessions} do
    {:ok, _view, _html, id} = Sessions.live(sessions, build_conn(), "/layout")
    assert {:ok, %Recording{layout: {"PhoenixReplay.Test.Layouts", "app"}}} = Buffer.fetch(id)

    {:ok, _view, _html, id} = Sessions.live(sessions, build_conn(), "/layout?layout=none")
    assert {:ok, %Recording{layout: false}} = Buffer.fetch(id)

    {:ok, _view, _html, id} = Sessions.live(sessions, build_conn(), "/counter")
    assert {:ok, %Recording{layout: false}} = Buffer.fetch(id)
  end

  test "saves the recording when the view exits", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/counter")
    render_click(view, "inc")

    assert Sessions.stop(sessions, view) == :persisted
    assert Buffer.fetch(id) == :error
    assert {:ok, recording} = Storage.fetch(Fixtures.storage(), id)
    assert Timeline.at(recording, Timeline.last_index(recording)).assigns.count == 1
  end

  test "sanitizes params and assigns", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/form")
    render_change(view, "validate", %{"name" => "dan", "password" => "hunter2"})

    {:ok, recording} = Buffer.fetch(id)
    refute inspect(recording) =~ "hunter2"

    assert %{name: "dan", password: "[FILTERED]"} =
             Timeline.at(recording, Timeline.last_index(recording)).assigns
  end

  test "applies live session options", %{sessions: sessions} do
    {:ok, view, _html, id} = Sessions.live(sessions, build_conn(), "/limited/counter")
    for _ <- 1..5, do: render_click(view, "inc")

    assert {:ok, %{events: events}} = Buffer.fetch(id)
    assert length(events) == 3
  end

  test "samples a visit as a whole: its recordings draw the same", %{sessions: sessions} do
    {sampled, skipped} =
      Enum.split_with(Enum.map(1..40, &"visit-#{&1}"), fn visit ->
        {draw, _keep} = PhoenixReplay.Session.Visits.draws(visit)
        Recorder.sampled?(0.5, draw)
      end)

    recorded? = fn visit, path ->
      kept = %{
        "visit" => %{"id" => visit, "seen" => System.system_time(:millisecond), "campaign" => nil}
      }

      conn = Plug.Test.init_test_session(build_conn(), %{"phoenix_replay" => kept})
      {:ok, view, _html} = live(conn, path)

      case :sys.get_state(view.pid).socket.private[:phoenix_replay] do
        %{id: _id} ->
          Sessions.track(sessions, view)
          true

        nil ->
          false
      end
    end

    for visit <- Enum.take(sampled, 2) do
      assert recorded?.(visit, "/half/counter") and recorded?.(visit, "/half/form")
    end

    for visit <- Enum.take(skipped, 2) do
      refute recorded?.(visit, "/half/counter") or recorded?.(visit, "/half/form")
    end
  end

  test "records only the sampled share of sessions" do
    {:ok, view, _html} = live(build_conn(), "/unsampled/counter")
    render_click(view, "inc")

    refute Map.has_key?(:sys.get_state(view.pid).socket.private, :phoenix_replay)
  end

  test "records LiveViews not mounted at the router", %{sessions: sessions} do
    {:ok, view, _html} = live_isolated(build_conn(), PhoenixReplay.Test.Live.Embedded)
    id = Sessions.track(sessions, view)
    render_click(view, "inc")

    assert {:ok, %{url: nil, events: events}} = Buffer.fetch(id)
    assert Enum.any?(events, &(&1.type == :event))
    refute Enum.any?(events, &(&1.type == :params))
  end

  test "samples sessions from a uniform draw" do
    assert Recorder.sampled?(1.0, 0.99)
    refute Recorder.sampled?(0.0, 0.0)
    assert Recorder.sampled?(0.25, 0.25)
    refute Recorder.sampled?(0.25, 0.26)
  end

  test "rejects unknown live session options" do
    socket = %Phoenix.LiveView.Socket{}

    assert_raise ArgumentError, ~r/:storage/, fn ->
      PhoenixReplay.Recorder.on_mount([storage: Foo], %{}, %{}, socket)
    end
  end

  describe "client context" do
    @iphone "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1"

    defp client_conn do
      build_conn()
      |> put_connect_params(%{
        "_replay" => %{"width" => 390, "height" => 844, "dpr" => 3, "tab" => "tab-1"},
        "_live_referer" => "http://www.example.com/form"
      })
      |> Plug.Conn.put_private(:live_view_connect_info, %{user_agent: @iphone})
    end

    test "records the viewport, user agent, tab and previous page the client sent", %{
      sessions: sessions
    } do
      {:ok, _view, _html, id} = Sessions.live(sessions, client_conn(), "/counter")

      assert {:ok, %{client: client}} = Buffer.fetch(id)

      # The visit and landing come from PhoenixReplay.Plug on the server, not from the client.
      assert is_binary(client.visit)

      assert %{client | visit: nil, landing: nil} == %PhoenixReplay.Recording.Client{
               viewport: %{width: 390, height: 844, dpr: 3},
               user_agent: @iphone,
               tab: "tab-1",
               navigated_from: "http://www.example.com/form"
             }
    end

    test "records nothing the client did not send", %{sessions: sessions} do
      conn = put_connect_params(build_conn(), %{"_live_referer" => "undefined"})
      {:ok, _view, _html, id} = Sessions.live(sessions, conn, "/counter")

      assert {:ok, %{client: %PhoenixReplay.Recording.Client{} = client}} = Buffer.fetch(id)
      assert %{client | visit: nil, landing: nil} == %PhoenixReplay.Recording.Client{}
    end

    test "records viewport changes sent with events, leaving them out of params", %{
      sessions: sessions
    } do
      {:ok, view, _html, id} = Sessions.live(sessions, client_conn(), "/counter")
      same = %{"_replay" => %{"width" => 390, "height" => 844, "dpr" => 3}}
      rotated = %{"_replay" => %{"width" => 844, "height" => 390, "dpr" => 3}}

      render_click(view, "inc", same)
      render_click(view, "inc", rotated)
      render_click(view, "inc", rotated)

      {:ok, recording} = Buffer.fetch(id)
      types = recording.events |> Enum.map(& &1.type) |> Enum.filter(&(&1 in [:event, :viewport]))
      assert types == [:event, :viewport, :event, :event]

      assert %Event{data: %{width: 844, height: 390}} =
               Enum.find(recording.events, &(&1.type == :viewport))

      assert Enum.all?(recording.events, &(not Map.has_key?(&1.data[:params] || %{}, "_replay")))
      # Which code it was made with.
      assert Map.has_key?(recording.code.modules, "PhoenixReplay.Test.Live.Counter")
      assert Timeline.at(recording, Timeline.last_index(recording)).viewport.width == 844
    end

    test "records an event an app hook handled and halted, before the recorder's hooks", %{
      sessions: sessions
    } do
      {:ok, view, _html, id} = Sessions.live(sessions, client_conn(), "/hooked/counter")
      render_click(view, "inc")
      render_click(view, "reset", %{"to" => "zero"})

      {:ok, recording} = Buffer.fetch(id)

      assert [{"inc", %{}}, {"reset", %{"to" => "zero"}}] =
               for(
                 %Event{type: :event, data: data} <- recording.events,
                 do: {data.name, data.params}
               )
    end

    test "keeps only the media settings the :client config asks for", %{sessions: sessions} do
      previous = Application.get_env(:phoenix_replay, :client)

      Application.put_env(:phoenix_replay, :client,
        media: [:color_scheme],
        landing: [timeout: 50]
      )

      on_exit(fn -> Application.put_env(:phoenix_replay, :client, previous) end)

      {:ok, view, _html, id} = Sessions.live(sessions, client_conn(), "/counter")

      sent = %{
        "width" => 390,
        "height" => 844,
        "dpr" => 3,
        "angle" => 90,
        "color_scheme" => "dark",
        "pointer" => "coarse",
        "hover" => "none"
      }

      render_click(view, "inc", %{"_replay" => sent})
      {:ok, recording} = Buffer.fetch(id)

      assert %Event{data: viewport} = Enum.find(recording.events, &(&1.type == :viewport))
      assert viewport == %{width: 390, height: 844, dpr: 3, angle: 90, color_scheme: :dark}
    end

    test "records the screen's angle and the media settings, dropping unknown values", %{
      sessions: sessions
    } do
      {:ok, view, _html, id} = Sessions.live(sessions, client_conn(), "/counter")

      dark = %{
        "width" => 390,
        "height" => 844,
        "dpr" => 3,
        "angle" => 0,
        "color_scheme" => "dark",
        "reduced_motion" => true,
        "contrast" => "brighter",
        "pointer" => "coarse"
      }

      render_click(view, "inc", %{"_replay" => dark})

      {:ok, recording} = Buffer.fetch(id)

      assert %Event{data: viewport} = Enum.find(recording.events, &(&1.type == :viewport))

      assert viewport == %{
               width: 390,
               height: 844,
               dpr: 3,
               angle: 0,
               color_scheme: :dark,
               reduced_motion: true,
               pointer: :coarse
             }
    end
  end
end
