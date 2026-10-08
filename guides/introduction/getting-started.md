# Getting Started

PhoenixReplay needs Elixir 1.18 or later and Phoenix LiveView 1.1 or later.

## Install with Igniter

```bash
mix igniter.install phoenix_replay
```

The installer imports PhoenixReplay's formatter settings, mounts the dashboard at `/dev/replay` behind your `:dev_routes` flag (like Phoenix's LiveDashboard), turns recording off in `config/test.exs`, and ignores the local recordings directory. It also sends [browser context](../features/recording.md#browser-and-journey) to recordings: it adds `:user_agent` to your LiveView socket's `connect_info`, passes PhoenixReplay's client helpers to `LiveSocket` in `assets/js/app.js` when that file still has the setup Phoenix generates, and adds `PhoenixReplay.Plug` to your `:browser` pipeline for [visit context](../features/recording.md#visit-context). It then prints how to record a live session, which is the step below.

## Install manually

Add the dependency:

```elixir
def deps do
  [{:phoenix_replay, "~> 0.6"}]
end
```

Add `:phoenix_replay` to `import_deps` in `.formatter.exs`, so `mix format` leaves the router macro without parentheses:

```elixir
[
  import_deps: [:ecto, :phoenix, :phoenix_replay],
  # ...
]
```

Turn recording off in `config/test.exs`; see [Testing](#testing).

Optionally, send the browser's viewport, user agent and tab with recordings, as [Browser and journey](../features/recording.md#browser-and-journey) describes.

## Record a live session

Add `PhoenixReplay.Recorder` to the `on_mount` hooks of the live sessions you want to record:

```elixir
live_session :default, on_mount: [PhoenixReplay.Recorder] do
  live "/", HomeLive
  live "/checkout", CheckoutLive
end
```

Every connected LiveView in the session is now recorded, including its LiveComponents. Nothing changes in your views or components, and the JavaScript side is optional.

## Mount the dashboard

Import the router macro and mount the dashboard behind your own authentication:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  import PhoenixReplay.Router

  scope "/admin" do
    pipe_through [:browser, :require_admin]

    phoenix_replay "/replay"
  end
end
```

Recordings can contain business data, so never mount the dashboard on a public route. See [Privacy and Security](privacy-and-security.md).

## Watch a replay

Start your app, use a recorded page for a while, then navigate away or close the tab. Open `/admin/replay`: the session is listed with its view, page, device, start time, duration, event count and errors. Click its row to replay it.

The player re-renders your view inside an iframe with the assigns recorded at each event. Move through it with the timeline, the event list, or the keyboard: with the timeline focused, `←` and `→` step and `Space` plays or pauses. The **State** tab shows the assigns at each moment, and **Copy link** shares the moment you are looking at.

## Testing

Your LiveView tests mount connected views, so with the recorder in your live sessions they would record sessions and save them to storage during every test run. Turn recording off in `config/test.exs`:

```elixir
config :phoenix_replay, sample_rate: 0.0
```

To test a flow with recording on, give its live session its own rate. Per-session options override the global configuration:

```elixir
live_session :checkout, on_mount: [{PhoenixReplay.Recorder, sample_rate: 1.0}] do
  live "/checkout", CheckoutLive
end
```

and point `:storage` at a temporary directory in `config/test.exs`. Sanitizers and authorization modules are plain modules, so test them by calling their callbacks directly.

## Next steps

- [Recording](recording.md) — what is recorded, sampling and limits
- [Dashboard](dashboard.md) — authorization, filters and the replay frame
- [Storage](storage.md) — files, Ecto and retention
- [Configuration cheatsheet](configuration.cheatmd)
