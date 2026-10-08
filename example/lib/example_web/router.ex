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
    plug ExampleWeb.Theme
  end

  scope "/", ExampleWeb do
    pipe_through :browser

    live_session :recorded, on_mount: [PhoenixReplay.Recorder, {ExampleWeb.Theme, :default}] do
      live "/", TaskLive.Index, :index
      live "/tasks/new", TaskLive.Index, :new
      live "/tasks/:id/edit", TaskLive.Index, :edit
      live "/search", SearchLive
    end
  end

  scope "/" do
    pipe_through :browser

    # Replays render inside the app's own root layout, so assets resolve
    # through Volt's manifest in production.
    phoenix_replay "/replay", frame_layout: {ExampleWeb.Layouts, :root}
  end

  if Application.compile_env(:example, :dev_routes) do
    scope "/dev", ExampleWeb do
      pipe_through :browser

      live_session :catalog, root_layout: {ExampleWeb.Catalog.Layout, :root} do
        live "/components", Catalog.Live
      end
    end
  end
end
