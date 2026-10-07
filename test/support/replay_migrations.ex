defmodule PhoenixReplay.Test.ReplayMigrations.ClicksToCount do
  @moduledoc "Recordings made when the counter's `:count` was `:clicks`."
  use PhoenixReplay.Migration, version: 20_261_007_120_000

  @impl true
  def up(PhoenixReplay.Test.Live.Counter, %{clicks: clicks} = assigns),
    do: Map.put_new(assigns, :count, clicks)

  def up(_view_or_component, assigns), do: assigns
end
