defmodule PhoenixReplay.Web.Export.ErrorHTML do
  @moduledoc """
  Renders errors of `PhoenixReplay.Web.Export.Endpoint` as their status text,
  such as "Not Found" for a page asked for with an invalid token. Only the
  export browser sees them.
  """

  @doc "The status text for a template such as `\"404.html\"`."
  @spec render(String.t(), map()) :: String.t()
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
