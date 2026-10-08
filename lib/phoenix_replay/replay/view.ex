defmodule PhoenixReplay.Replay.View do
  @moduledoc """
  How one LiveView renders in a replay. For the whole app, such as
  adapting the assigns older recordings have, see `PhoenixReplay.Replay`.

  A LiveView whose live render depends on code in the browser, such as a
  list a script filters, can say how to render without that code.

      defmodule MyAppWeb.SearchLive do
        use MyAppWeb, :live_view
        @behaviour PhoenixReplay.Replay.View

        @impl PhoenixReplay.Replay.View
        def replay_render(assigns) do
          query = get_in(assigns.phoenix_replay_state, ["search", "query"])
          assigns |> assign(:query, query) |> render()
        end
      end

  The replay frame calls `c:replay_render/1` instead of `render/1` when the
  view defines it; see `PhoenixReplay.Web.Rendering.render/2`. Declaring
  the behaviour is optional, but lets `@impl` and Dialyzer check the
  callback.
  """

  @doc """
  Renders the view in a replay, with the recorded assigns and the client
  state recorded up to that moment in `@phoenix_replay_state`: a map of
  each reported key to its merged fields, with string keys.

  It renders in full on every step, without change tracking, so assigns
  derived here with `assign/3` always show.
  """
  @callback replay_render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @optional_callbacks replay_render: 1
end
