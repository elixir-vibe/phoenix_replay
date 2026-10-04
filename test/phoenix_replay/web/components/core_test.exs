defmodule PhoenixReplay.Web.Components.CoreTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest
  import PhoenixReplay.Web.Components.Core

  defp pages(page, total_pages) do
    assigns = %{page: page, total_pages: total_pages}

    ~H"""
    <.pagination page={@page} total_pages={@total_pages} path={&"/?page=#{&1}"} />
    """
    |> rendered_to_string()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("a, span")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
  end

  test "numbers pages around the current one, with gaps for skipped runs" do
    assert pages(1, 1) == []
    assert pages(1, 3) == ["1", "2", "3", "›"]
    assert pages(5, 12) == ["‹", "1", "…", "4", "5", "6", "…", "12", "›"]
    # A gap of one page shows that page instead.
    assert pages(4, 12) == ["‹", "1", "2", "3", "4", "5", "…", "12", "›"]
    assert pages(12, 12) == ["‹", "1", "…", "11", "12"]
  end

  test "marks the current page and option for assistive technology" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <.pagination page={2} total_pages={3} path={&"/?page=#{&1}"} />
      <.segmented label="Size" options={[{"fit", "Fit"}, {"actual", "100%"}]} value="fit" event="size" />
      <.chip pressed={false}>Logs</.chip>
      """)

    doc = LazyHTML.from_fragment(html)

    texts =
      &(doc |> LazyHTML.query(&1) |> Enum.map(fn node -> String.trim(LazyHTML.text(node)) end))

    assert texts.(~s(a[aria-current="page"])) == ["2"]
    assert texts.(~s(button[aria-pressed="true"])) == ["Fit"]
    assert texts.(~s(button[aria-pressed="false"])) == ["100%", "Logs"]
  end
end
