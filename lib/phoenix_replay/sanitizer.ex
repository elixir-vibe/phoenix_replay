defmodule PhoenixReplay.Sanitizer do
  @moduledoc """
  Behaviour for removing sensitive or bulky data before it is recorded.

  `sanitize_assigns/1` receives LiveView assigns (atom keys) for the initial
  mount and for each render's changed keys. `sanitize_params/1` receives event
  params, URL params and the session (string keys).

  The default implementation is `PhoenixReplay.Sanitizer.Default`. A custom
  sanitizer can delegate to it for the parts it does not change:

      defmodule MyApp.ReplaySanitizer do
        @behaviour PhoenixReplay.Sanitizer

        @impl true
        def sanitize_assigns(assigns) do
          assigns
          |> Map.drop([:current_user])
          |> PhoenixReplay.Sanitizer.Default.sanitize_assigns()
        end

        @impl true
        defdelegate sanitize_params(params), to: PhoenixReplay.Sanitizer.Default
      end

      config :phoenix_replay, sanitizer: MyApp.ReplaySanitizer
  """

  @callback sanitize_assigns(map()) :: map()
  @callback sanitize_params(map()) :: map()
end
