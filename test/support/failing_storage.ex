defmodule PhoenixReplay.Test.FailingStorage do
  @moduledoc "Storage backend whose writes always fail, reporting each attempt to `:notify`."

  @behaviour PhoenixReplay.Storage

  @impl true
  def save(recording, opts) do
    if pid = opts[:notify], do: send(pid, {:save_attempt, recording.id})
    {:error, :unavailable}
  end

  @impl true
  def fetch(_id, _opts), do: {:error, :not_found}

  @impl true
  def list(_opts), do: []

  @impl true
  def delete(_id, _opts), do: :ok

  @impl true
  def clear(_opts), do: :ok
end
