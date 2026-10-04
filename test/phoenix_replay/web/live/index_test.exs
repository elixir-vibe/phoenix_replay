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

  test "refreshes when recordings change" do
    {:ok, view, _html} = live(build_conn(), "/replay")
    save("fresh")
    Recordings.broadcast_change()

    assert render(view) =~ "recording-fresh"
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
