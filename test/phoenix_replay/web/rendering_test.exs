defmodule PhoenixReplay.Web.RenderingTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias PhoenixReplay.Web.Rendering

  defmodule Layouts do
    use Phoenix.Component

    def app(assigns) do
      ~H"""
      <nav>Menu</nav>
      <p :if={@flash["error"]} role="alert">{@flash["error"]}</p>
      {@inner_content}
      """
    end
  end

  defmodule LayoutView do
    use Phoenix.LiveView, layout: {Layouts, :app}

    def render(assigns), do: ~H"<main>{@count}</main>"
  end

  defmodule PlainView do
    use Phoenix.LiveView

    def render(assigns), do: ~H"<main>{@count}</main>"
  end

  test "renders a view in the layout its layout: option names, with the recorded flash" do
    assigns = %{__changed__: nil, count: 3, flash: %{"error" => "Below zero"}}
    html = LayoutView |> Rendering.render(assigns) |> rendered_to_string()

    assert html =~ "<nav>Menu</nav>"
    assert html =~ ~s(<p role="alert">Below zero</p>)
    assert html =~ "<main>3</main>"
  end

  test "renders a view without a layout option alone" do
    html = PlainView |> Rendering.render(%{__changed__: nil, count: 3}) |> rendered_to_string()
    assert html == "<main>3</main>"
  end

  test "prefers the layout the recording kept over the view's option" do
    assigns = %{__changed__: nil, count: 3, flash: %{}}
    recorded = {inspect(Layouts), "app"}

    assert PlainView
           |> Rendering.render(assigns, layout: recorded)
           |> rendered_to_string() =~ "<nav>Menu</nav>"

    # A mount that returned `layout: false` rendered the view alone live.
    assert LayoutView |> Rendering.render(assigns, layout: false) |> rendered_to_string() ==
             "<main>3</main>"
  end

  test "leaves out a recorded layout whose module no longer exists" do
    html =
      PlainView
      |> Rendering.render(%{__changed__: nil, count: 3}, layout: {"Gone.Layouts9f2c", "app"})
      |> rendered_to_string()

    assert html == "<main>3</main>"
  end

  test "describes a missing assign without dumping every assign" do
    assigns = %{__changed__: %{}, tasks: List.duplicate("task", 500)}

    assert Rendering.describe(%KeyError{key: :filter, term: assigns}) ==
             "the recording has no @filter"

    assert Rendering.describe(%KeyError{key: :name, term: %{other: 1}}) ==
             "key :name not found"
  end

  test "keeps the first line of other messages, shortened" do
    assert Rendering.describe(%RuntimeError{message: "boom\nmore detail"}) == "boom"

    assert %RuntimeError{message: String.duplicate("x", 500)}
           |> Rendering.describe()
           |> String.length() == 201
  end
end
