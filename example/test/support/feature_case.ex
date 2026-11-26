defmodule ExampleWeb.FeatureCase do
  @moduledoc """
  The case for browser tests: a Fluffy session in Chromium.
  """

  use ExUnit.CaseTemplate

  using opts do
    quote do
      use Playwright.Test, unquote(opts)

      setup do
        %{conn: Fluffy.start_session(:playwright)}
      end
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Example.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
