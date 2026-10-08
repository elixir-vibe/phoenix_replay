defmodule PhoenixReplay.Test.Router do
  @moduledoc "Router with recorded views and two dashboard mounts."

  use Phoenix.Router

  import Phoenix.LiveView.Router
  import PhoenixReplay.Router

  pipeline :browser do
    plug :fetch_session
    plug :protect_from_forgery
    plug PhoenixReplay.Plug
  end

  scope "/" do
    pipe_through :browser

    live_session :recorded, on_mount: [PhoenixReplay.Recorder] do
      live "/counter", PhoenixReplay.Test.Live.Counter
      live "/form", PhoenixReplay.Test.Live.Form
      live "/cart", PhoenixReplay.Test.Live.Cart
      live "/async", PhoenixReplay.Test.Live.AsyncPage
    end

    live_session :hooked,
      on_mount: [{PhoenixReplay.Test.Live.HaltingHook, :default}, PhoenixReplay.Recorder] do
      live "/hooked/counter", PhoenixReplay.Test.Live.Counter
    end

    live_session :unsampled, on_mount: [{PhoenixReplay.Recorder, sample_rate: 0.0}] do
      live "/unsampled/counter", PhoenixReplay.Test.Live.Counter
    end

    live_session :limited, on_mount: [{PhoenixReplay.Recorder, max_events: 3}] do
      live "/limited/counter", PhoenixReplay.Test.Live.Counter
    end

    live_session :pointer,
      on_mount: [{PhoenixReplay.Recorder, pointer: [sample: 30, flush: 500]}] do
      live "/pointer/counter", PhoenixReplay.Test.Live.Counter
    end

    live_session :flushed,
      on_mount: [{PhoenixReplay.Recorder, flush: [events: 2, interval: 60_000]}] do
      live "/flushed/counter", PhoenixReplay.Test.Live.Counter
    end

    live_session :collected, on_mount: [{PhoenixReplay.Recorder, redact: ["card-\\d+"]}] do
      live "/telemetry", PhoenixReplay.Test.Live.TelemetryPage
    end

    live_session :tail_sampled,
      on_mount: [{PhoenixReplay.Recorder, keep: [rate: 0.0, errors: true, slower_than: 100]}] do
      live "/tail/counter", PhoenixReplay.Test.Live.Counter
      live "/tail/telemetry", PhoenixReplay.Test.Live.TelemetryPage
    end

    phoenix_replay "/replay"
  end

  scope "/restricted" do
    pipe_through :browser

    phoenix_replay "/replay", authorize: PhoenixReplay.Test.Authorization, as: :restricted_replay
  end

  scope "/app" do
    pipe_through :browser

    phoenix_replay "/replay", frame_layout: {PhoenixReplay.Test.Layouts, :root}, as: :app_replay
  end
end
