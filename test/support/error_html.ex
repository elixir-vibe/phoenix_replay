defmodule PhoenixReplay.Test.ErrorHTML do
  @moduledoc "Renders error pages as their status message."

  @doc "Renders the status message for `template`."
  @spec render(String.t(), map()) :: String.t()
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
