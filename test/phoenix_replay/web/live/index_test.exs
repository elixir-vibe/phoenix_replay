defmodule PhoenixReplay.Web.Live.IndexTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PhoenixReplay.{Recordings, Storage}
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
    refute html =~ "Clear all"
  end

  test "lists recordings and links to them" do
    save("stored")
    {:ok, view, html} = live(build_conn(), "/replay")

    assert html =~ "PhoenixReplay.Test.Live.Counter"
    assert has_element?(view, ~s(a[href="/replay/stored"]))
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

    view |> element("#recording-one button", "Delete") |> render_click()
    refute has_element?(view, "#recording-one")

    view |> element("button", "Clear all") |> render_click()
    refute has_element?(view, "#recording-two")
  end

  test "applies authorization" do
    save("public")
    save("secret-1")
    {:ok, view, html} = live(build_conn(), "/restricted/replay")

    assert has_element?(view, ~s(#recording-public a[href="/restricted/replay/public"]))
    refute html =~ "secret-1"
    refute html =~ "Clear all"
    assert render_click(view, "delete", %{"id" => "secret-1"})
    assert {:ok, _recording} = Storage.fetch(Fixtures.storage(), "secret-1")
  end

  test "paginates" do
    for i <- 1..26, do: save("page-#{i}")
    {:ok, view, html} = live(build_conn(), "/replay")
    assert html =~ "Page 1 / 2"

    html = view |> element("a", "Next") |> render_click()
    assert html =~ "Page 2 / 2"
  end
end
