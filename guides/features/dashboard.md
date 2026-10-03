# Dashboard

## Mounting

`PhoenixReplay.Router.phoenix_replay/2` defines the dashboard routes under a path:

```elixir
scope "/admin" do
  pipe_through [:browser, :require_admin]

  phoenix_replay "/replay",
    on_mount: [{MyAppWeb.UserAuth, :ensure_admin}],
    authorize: MyApp.ReplayAuthorization
end
```

| Option | Purpose |
|---|---|
| `:on_mount` | Your hooks, typically authentication that assigns the current user |
| `:authorize` | A `PhoenixReplay.Authorization` module |
| `:frame_layout` | Root layout for the replay frame, see below |
| `:live_socket_path` | Your LiveView socket path, default `"/live"` |
| `:as` | Live session name prefix, needed only to mount the dashboard twice |

## Authorization

Implement `PhoenixReplay.Authorization` to decide per action and recording:

```elixir
defmodule MyApp.ReplayAuthorization do
  @behaviour PhoenixReplay.Authorization

  @impl true
  def authorize(:clear, _subject, socket), do: socket.assigns.current_user.admin?
  def authorize(_action, _recording, socket), do: socket.assigns.current_user != nil
end
```

Actions are `:list`, `:view`, `:delete` and `:clear`. The socket's assigns include what your `:on_mount` hooks set. Recordings a viewer may not see respond with 404, the same as missing ones.

## Finding recordings

The index lists sessions still running first, marked live, then stored recordings. Filter by:

- text in the URL or recording id,
- view module,
- an event the session triggered, with suggestions from recorded event names,
- start time within the last hour, day or week,
- minimum number of events.

Filters are URL parameters, such as `/admin/replay?view=MyAppWeb.CheckoutLive&event=pay&within=24h`, so a filtered list can be shared or bookmarked. `PhoenixReplay.Recordings.Filter` applies the same criteria in code.

## Player

The player shows the replayed page, a timeline with a marker per event, the event list and the assigns at the current position. Play at 1×, 2×, 5× or 10×, click or drag the timeline, click an event to jump to it, or focus the timeline and use `←`, `→` and `Space`.

Each viewer drives a private frame, so several people can watch the same recording independently.

## The replay frame

The frame renders your views, so it needs your stylesheet. By default it loads `/assets/css/app.css` through your endpoint's `static_path/1`, which suits the stock esbuild and Tailwind setup.

If your assets are content-hashed by a bundler such as [Volt](https://hexdocs.pm/volt), render the frame in your own root layout:

```elixir
phoenix_replay "/replay", frame_layout: {MyAppWeb.Layouts, :root}
```

Interaction in the frame is ignored: recorded templates keep their `phx-click` bindings, but the frame does not act on them.

## Assets

The dashboard serves its own small script and stylesheet at content-hashed paths, and loads your application's own `phoenix` and `phoenix_live_view` client files, so the LiveView client always matches your server version. It needs nothing from your asset pipeline. Responses are public and cacheable, and work behind `:protect_from_forgery`.
