defmodule PhoenixReplay.Test.Layouts do
  @moduledoc "An app's root layout, whose `<html>` follows an assign, as a theme would."
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-count={assigns[:count]}>
      <head></head>
      <body>{@inner_content}</body>
    </html>
    """
  end
end
