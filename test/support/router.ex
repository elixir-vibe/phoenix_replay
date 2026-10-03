defmodule PhoenixReplay.Test.Router do
  @moduledoc "Router with recorded views and two dashboard mounts."

  use Phoenix.Router

  import Phoenix.LiveView.Router
  import PhoenixReplay.Router

  pipeline :browser do
    plug :fetch_session
    plug :protect_from_forgery
  end

  scope "/" do
    pipe_through :browser

    live_session :recorded, on_mount: [PhoenixReplay.Recorder] do
      live "/counter", PhoenixReplay.Test.Live.Counter
      live "/form", PhoenixReplay.Test.Live.Form
    end

    phoenix_replay "/replay"
  end

  scope "/restricted" do
    pipe_through :browser

    phoenix_replay "/replay", authorize: PhoenixReplay.Test.Authorization, as: :restricted_replay
  end
end
