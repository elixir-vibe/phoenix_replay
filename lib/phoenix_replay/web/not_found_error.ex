defmodule PhoenixReplay.Web.NotFoundError do
  @moduledoc """
  Raised when a recording does not exist or the viewer may not see it.

  Rendered by Phoenix as a 404 response.
  """

  defexception [:id, plug_status: 404]

  @impl true
  def message(%{id: id}), do: "recording #{inspect(id)} not found"
end
