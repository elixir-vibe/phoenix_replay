defmodule ExampleWeb.Router do
  use ExampleWeb, :router
  import PhoenixReplay.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ExampleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug PhoenixReplay.Plug
  end

  scope "/", ExampleWeb do
    pipe_through :browser

    live_session :recorded, on_mount: [PhoenixReplay.Recorder] do
      live "/", TaskLive.Index, :index
      live "/tasks/new", TaskLive.Index, :new
      live "/tasks/:id/edit", TaskLive.Index, :edit
    end
  end

  scope "/" do
    pipe_through :browser

    # Replays render inside the app's own root layout, so assets resolve
    # through Volt's manifest in production.
    phoenix_replay "/replay", frame_layout: {ExampleWeb.Layouts, :root}
  end
end
