defmodule PhoenixReplay.Web.HighlightTest do
  use ExUnit.Case, async: true

  alias PhoenixReplay.Web.Highlight

  defp html(safe), do: Phoenix.HTML.safe_to_string(safe)

  test "highlights SQL and inspected terms with Lumis's classes" do
    assert html(Highlight.code("SELECT 1", :sql)) =~ ~s(<span class="l-keyword">SELECT</span>)
    assert html(Highlight.term(%{ok: true})) =~ ~s(<span class="l-boolean">true</span>)
  end

  test "shows a recorded list of small integers as numbers, not a charlist" do
    shown = html(Highlight.term(%{"ids" => [11]}))
    assert shown =~ "11"
    refute shown =~ "~c"
  end

  test "escapes what it highlights" do
    refute html(Highlight.code(~s(SELECT '<script>'), :sql)) =~ "<script>"
    refute html(Highlight.term("<b>")) =~ "<b>"
  end
end
