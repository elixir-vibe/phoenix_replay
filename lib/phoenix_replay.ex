defmodule PhoenixReplay do
  @moduledoc """
  Session recording and replay for Phoenix LiveView.

  PhoenixReplay records each LiveView session as a timeline of events and
  assigns changes, and replays it by re-rendering the view's own template
  with the recorded assigns. No client-side recording is involved.

  Record a live session with `PhoenixReplay.Recorder`:

      live_session :default, on_mount: [PhoenixReplay.Recorder] do
        live "/dashboard", DashboardLive
      end

  and mount the dashboard with `PhoenixReplay.Router.phoenix_replay/2`.
  Configuration is described in `PhoenixReplay.Config`; storage, sanitizing
  and authorization are pluggable through `PhoenixReplay.Storage`,
  `PhoenixReplay.Sanitizer` and `PhoenixReplay.Authorization`.
  """
end
