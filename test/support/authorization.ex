defmodule PhoenixReplay.Test.Authorization do
  @moduledoc "Denies recordings whose id starts with `secret`, and clearing."

  @behaviour PhoenixReplay.Authorization

  @impl true
  def authorize(:clear, nil, _socket), do: false
  def authorize(_action, %{id: "secret" <> _rest}, _socket), do: false
  def authorize(_action, _subject, _socket), do: true
end
