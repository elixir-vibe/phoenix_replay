defmodule PhoenixReplay.Web.Export.Router do
  @moduledoc """
  The pages of `PhoenixReplay.Web.Export.Endpoint`: the stage the browser
  films (`PhoenixReplay.Web.Export.Stage`), the replay frame inside it
  (`PhoenixReplay.Web.Live.Frame`) and the dashboard's assets. Both pages
  check their token with `PhoenixReplay.Web.Export.Access`.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  @context %{
    base_path: "/_phoenix_replay",
    authorize: nil,
    live_socket_path: "/_phoenix_replay/live"
  }

  pipeline :stage do
    plug :fetch_query_params
    plug :fetch_session
  end

  scope "/_phoenix_replay" do
    pipe_through :stage

    get "/assets/:asset", PhoenixReplay.Web.Assets, []

    live_session :phoenix_replay_export_stage,
      on_mount: [{PhoenixReplay.Web.Context, @context}, PhoenixReplay.Web.Export.Access],
      root_layout: {PhoenixReplay.Web.Layouts, :dashboard} do
      live "/stage/:token", PhoenixReplay.Web.Export.Stage, :stage, as: :stage
    end

    live_session :phoenix_replay_export_frame,
      on_mount: [{PhoenixReplay.Web.Context, @context}, PhoenixReplay.Web.Export.Access],
      root_layout: {PhoenixReplay.Web.Export.Access, :frame_layout} do
      live "/frame/:token/:id", PhoenixReplay.Web.Live.Frame, :frame, as: :frame
    end
  end
end
