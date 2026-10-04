defmodule PhoenixReplay.Web.Live.IndexTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Config, Recordings, Storage}
  alias PhoenixReplay.Session.Buffer
  alias PhoenixReplay.Test.Fixtures

  @endpoint PhoenixReplay.Test.Endpoint

  setup do
    Storage.clear(Fixtures.storage())
    on_exit(fn -> Storage.clear(Fixtures.storage()) end)
  end

  defp save(id), do: Storage.save(Fixtures.storage(), Fixtures.counter_recording(id: id))

  defp save_at(id, connected_at) do
    Storage.save(
      Fixtures.storage(),
      Fixtures.counter_recording(id: id, connected_at: connected_at)
    )
  end

  test "shows an empty state" do
    {:ok, _view, html} = live(build_conn(), "/replay")
    assert html =~ "No recordings yet."
    refute html =~ "Delete all recordings"
  end

  test "lists recordings, each row one link to it" do
    save("stored")
    {:ok, view, html} = live(build_conn(), "/replay")

    assert html =~ "PhoenixReplay.Test.Live.Counter"

    assert [_one] =
             view
             |> render()
             |> LazyHTML.from_document()
             |> LazyHTML.query("#recording-stored a")
             |> Enum.to_list()

    assert has_element?(view, ~s(#recording-stored a[href="/replay/stored"]))
    refute html =~ "Open"
  end

  test "shows the device and source of each session" do
    recording = Fixtures.counter_recording(id: "phone")

    client =
      Map.merge(recording.client, %{
        viewport: %{width: 390, height: 844, dpr: 3},
        user_agent:
          "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " <>
            "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
        landing: %{path: "/", at: 0, params: %{"utm_source" => "hn"}, referrer: nil}
      })

    Storage.save(Fixtures.storage(), %{recording | client: client})
    {:ok, view, _html} = live(build_conn(), "/replay?errors=1&view=X")
    assert has_element?(view, "#recording-filter-toggle", "2")

    {:ok, view, _html} = live(build_conn(), "/replay")
    row = view |> element("#recording-phone") |> render()
    assert row =~ "Mobile Safari 18 on iOS"
    assert row =~ "from hn"
    assert row =~ ~s(aria-label="Phone")
  end

  test "lists running sessions apart, without delete, and counts sessions" do
    save("stored")
    recording = Fixtures.counter_recording(id: "running")
    :ok = Buffer.open(recording, self(), Config.load())
    on_exit(fn -> Buffer.close("running") end)

    {:ok, view, html} = live(build_conn(), "/replay")

    assert has_element?(view, "#recordings-live")
    assert has_element?(view, ~s(#recording-running a[href="/replay/running"]))
    refute has_element?(view, ~s(#recording-running button[aria-label^="Delete"]))
    assert has_element?(view, ~s(#recording-stored button[aria-label^="Delete"]))
    assert html =~ "2 sessions · 1 live · 0 with errors"
  end

  test "lists sessions that started earlier when they end, and counts newer ones" do
    {:ok, view, _html} = live(build_conn(), "/replay")
    until = :sys.get_state(view.pid).socket.assigns.until

    # A session that started before the list was read ends: it takes its place.
    save_at("ended", until - 60_000)
    # One that started later waits behind the banner, so rows do not shift.
    save_at("fresh", until + 1)

    Recordings.broadcast_change()

    assert has_element?(view, "#recording-ended")
    refute has_element?(view, "#recording-fresh")
    assert has_element?(view, "#recordings-new button", "1 new recording · Show")

    # Showing them reads the list as of now, which must be past "fresh".
    Process.sleep(2)
    view |> element("#recordings-new button") |> render_click()
    assert has_element?(view, "#recording-fresh")
    refute has_element?(view, "#recordings-new button")
  end

  test "deletes one or all recordings" do
    save("one")
    save("two")
    {:ok, view, _html} = live(build_conn(), "/replay")

    view |> element(~s(#recording-one button[aria-label^="Delete"])) |> render_click()
    refute has_element?(view, "#recording-one")

    view |> element("button", "Delete all recordings") |> render_click()
    refute has_element?(view, "#recording-two")
  end

  test "applies authorization" do
    save("public")
    save("secret-1")
    {:ok, view, html} = live(build_conn(), "/restricted/replay")

    assert has_element?(view, ~s(#recording-public a[href="/restricted/replay/public"]))
    refute html =~ "secret-1"
    refute html =~ "Delete all recordings"
    assert render_click(view, "delete", %{"id" => "secret-1"})
    assert {:ok, _recording} = Storage.fetch(Fixtures.storage(), "secret-1")
  end

  test "filters by URL params and keeps them while paginating" do
    for i <- 1..26, do: save("match-#{i}")
    save("other")

    {:ok, view, _html} = live(build_conn(), "/replay?q=match")
    assert has_element?(view, ~s(a[aria-current="page"]), "1")
    refute has_element?(view, "#recording-other")
    assert has_element?(view, ~s(a[href="/replay?page=2&q=match"]))
  end

  test "filter form patches the URL" do
    save("alpha")
    save("beta")
    {:ok, view, _html} = live(build_conn(), "/replay")

    view |> element("#recording-filter") |> render_change(%{"q" => "beta", "event" => "inc"})
    assert_patch(view, "/replay?event=inc&q=beta")
    assert has_element?(view, "#recording-beta")
    refute has_element?(view, "#recording-alpha")

    view |> element("#recording-filter") |> render_change(%{"q" => "nothing"})
    assert render(view) =~ "No recordings match these filters."
    view |> element("a", "Clear filters") |> render_click()
    assert has_element?(view, "#recording-alpha")
  end

  test "paginates" do
    for i <- 1..26, do: save("page-#{i}")
    {:ok, view, _html} = live(build_conn(), "/replay")
    assert has_element?(view, ~s(a[aria-current="page"]), "1")
    refute has_element?(view, ~s(a[aria-label="Previous page"]))

    view |> element(~s(a[aria-label="Next page"])) |> render_click()
    assert has_element?(view, ~s(a[aria-current="page"]), "2")
    refute has_element?(view, ~s(a[aria-label="Next page"]))
  end
end
