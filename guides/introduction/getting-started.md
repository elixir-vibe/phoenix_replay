# Getting Started

PhoenixReplay needs Elixir 1.18 or later and Phoenix LiveView 1.1 or later.

## Install

Add the dependency:

```elixir
def deps do
  [{:phoenix_replay, "~> 0.4"}]
end
```

Add `:phoenix_replay` to `import_deps` in `.formatter.exs`, so `mix format` leaves the router macro without parentheses:

```elixir
[
  import_deps: [:ecto, :phoenix, :phoenix_replay],
  # ...
]
```

## Record a live session

Add `PhoenixReplay.Recorder` to the `on_mount` hooks of the live sessions you want to record:

```elixir
live_session :default, on_mount: [PhoenixReplay.Recorder] do
  live "/", HomeLive
  live "/checkout", CheckoutLive
end
```

Every connected LiveView in the session is now recorded, including its LiveComponents. Nothing changes in your views, components or JavaScript.

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

Start your app, use a recorded page for a while, then navigate away or close the tab. Open `/admin/replay`: the session is listed with its view, start time, event count and duration. Open it to replay it.

The player re-renders your view inside an iframe with the assigns recorded at each event. Move through it with the timeline, the event list, or the keyboard: with the timeline focused, `←` and `→` step and `Space` plays or pauses.

## Next steps

- [Recording](recording.md) — what is recorded, sampling and limits
- [Dashboard](dashboard.md) — authorization, filters and the replay frame
- [Storage](storage.md) — files, Ecto and retention
- [Configuration cheatsheet](configuration.cheatmd)
