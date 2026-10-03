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

  Collected telemetry metadata and log metadata go through
  `sanitize_params/1` too. A sanitizer runs inside your LiveViews, so it
  should stay cheap; values that only detection can find, such as an email
  address in free text, are masked when the recording is saved by a
  `PhoenixReplay.Redactor`.
  """

  @callback sanitize_assigns(map()) :: map()
  @callback sanitize_params(map()) :: map()
end
