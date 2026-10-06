defmodule PhoenixReplay.Web.Live.IndexTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Catalog, Config, Storage}
  alias PhoenixReplay.Recording.Client.Landing
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

    client = %{
      recording.client
      | viewport: %{width: 390, height: 844, dpr: 3},
        user_agent:
          "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " <>
            "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
        landing: %Landing{path: "/", at: 0, params: %{"utm_source" => "hn"}}
    }

    Storage.save(Fixtures.storage(), %{recording | client: client})
    {:ok, view, _html} = live(build_conn(), "/replay")
    row = view |> element("#recording-phone") |> render()
    assert row =~ "Mobile Safari 18 on iOS"
    assert has_element?(view, ~s(#recording-phone a[href="/replay?source=hn"]), "hn")
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

  test "keeps its rows while sessions end, counting them in a banner" do
    save("listed")
    Process.sleep(2)
    {:ok, view, _html} = live(build_conn(), "/replay")
    until = :sys.get_state(view.pid).socket.assigns.until
    Process.sleep(2)

    # Saved after the list was read, whenever they started: a session that
    # started earlier would otherwise push the rows down.
    save_at("ended", until - 60_000)
    save_at("fresh", until + 1)
    Catalog.broadcast_change()

    assert has_element?(view, "#recording-listed")
    refute has_element?(view, "#recording-ended")
    refute has_element?(view, "#recording-fresh")
    assert has_element?(view, "#recordings-new button", "2 new recordings · Show")

    view |> element("#recordings-new button") |> render_click()
    assert has_element?(view, "#recording-ended")
    assert has_element?(view, "#recording-fresh")
    refute has_element?(view, "#recordings-new button")
  end

  test "reads storage once more for changes made just after a reload" do
    {:ok, view, _html} = live(build_conn(), "/replay")
    until = :sys.get_state(view.pid).socket.assigns.until

    save_at("first", until + 1)
    Catalog.broadcast_change()
    assert has_element?(view, "#recordings-new button", "1 new recording · Show")

    save_at("second", until + 2)
    Catalog.broadcast_change()
    assert has_element?(view, "#recordings-new button", "1 new recording · Show")

    send(view.pid, :reload_window)
    assert has_element?(view, "#recordings-new button", "2 new recordings · Show")
  end

  test "shows filters as chips, adds them from a menu and offers values with counts" do
    save("one")
    save("two")
    {:ok, view, _html} = live(build_conn(), "/replay?errors=1&view=Other&tab=t1")

    # Set fields are chips that change or remove them; unset ones are in the menu.
    assert has_element?(
             view,
             ~s(#recording-filter-errors[aria-pressed="true"][href="/replay?tab=t1&view=Other"])
           )

    assert has_element?(view, ~s([data-filter="view"]), "View is")

    assert has_element?(
             view,
             ~s([data-filter="view"] a[aria-label="Remove the View filter"][href="/replay?errors=1&tab=t1"])
           )

    assert has_element?(view, ~s([data-filter="tab"]), "This browser tab")
    assert has_element?(view, "#recording-filter-add-items button", "Event")
    refute has_element?(view, "#recording-filter-add-items button", "View")

    # The picker counts values among recordings matching the other criteria.
    {:ok, view, _html} = live(build_conn(), "/replay?view=Other")
    view |> element(~s([data-filter="view"] button)) |> render_click()
    assert has_element?(view, ~s(#recording-filter-value input[placeholder="Other"]))

    assert has_element?(
             view,
             ~s(#recording-filter-value a[href="/replay?view=PhoenixReplay.Test.Live.Counter"]),
             "2"
           )

    # Typing narrows the values; Enter filters by what was typed.
    view |> element("#recording-filter-value-form") |> render_change(%{"value" => "nothing"})
    refute has_element?(view, "#recording-filter-value a")
    view |> element("#recording-filter-value-form") |> render_submit(%{"value" => "Counter"})
    assert_patch(view, "/replay?view=Counter")
    refute has_element?(view, "#recording-filter-value")

    # A number is typed in.
    render_click(view, "edit_filter", %{"field" => "min_events"})
    view |> element("#recording-filter-value-form") |> render_submit(%{"value" => "3"})
    assert_patch(view, "/replay?min_events=3&view=Counter")

    render_click(view, "edit_filter", %{"field" => "event"})
    render_click(view, "close_filter", %{})
    refute has_element?(view, "#recording-filter-value")

    # Durations are picked from a few, and chips read naturally.
    render_click(view, "edit_filter", %{"field" => "longer_than"})

    assert has_element?(
             view,
             ~s(#recording-filter-value a[href="/replay?longer_than=60&min_events=3&view=Counter"]),
             "1 min"
           )

    {:ok, view, _html} = live(build_conn(), "/replay?longer_than=90&device_type=phone")
    assert has_element?(view, ~s([data-filter="longer_than"]), "Longer than")
    assert has_element?(view, ~s([data-filter="longer_than"]), "1 min 30 s")
    assert has_element?(view, ~s([data-filter="device_type"]), "Device is")
    assert has_element?(view, ~s([data-filter="device_type"]), "Phone")
    # Min events is no longer offered, but a link setting it shows its chip.
    refute has_element?(view, "#recording-filter-add-items button", "Min events")
  end

  test "shows the first page for page 0, and for a page past the end once emptied" do
    for i <- 1..26, do: save("page-#{i}")

    {:ok, view, _html} = live(build_conn(), "/replay?page=0")
    assert has_element?(view, ~s(a[aria-current="page"]), "1")

    {:ok, view, _html} = live(build_conn(), "/replay?page=2")
    view |> element("button", "Delete all recordings") |> render_click()
    assert render(view) =~ "No recordings yet."
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

    {:ok, view, _html} = live(build_conn(), "/replay?event=inc")
    # The search keeps the chips' criteria.
    view |> element("#recording-search") |> render_change(%{"q" => "beta"})
    assert_patch(view, "/replay?event=inc&q=beta")
    assert has_element?(view, "#recording-beta")
    refute has_element?(view, "#recording-alpha")

    view |> element("#recording-search") |> render_change(%{"q" => "nothing"})
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
