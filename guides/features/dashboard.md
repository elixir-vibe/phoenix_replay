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

Without an `:authorize` module, storage pages the recording list itself. With one, the dashboard reads every summary and checks `:list` for each, so pages and counts show exactly what the viewer may see.

## Finding recordings

The list shows sessions still running under **Live now**, then saved recordings in a table: the view, the page it started on, the device and where the visit came from, how long ago it started, its duration, event count and errors. An icon marks each session as a phone, tablet or desktop. Click anywhere on a row to open it; hover a saved row, or focus it from the keyboard, to delete it. **Delete all recordings** is in the ⋯ menu. A line above the list counts sessions, live ones and ones with errors.

Saved recordings are listed as of when you opened the list or last changed its filters, so rows stay put while sessions end. Recordings saved since then are counted in a **"3 new recordings · Show"** banner; showing them brings the list up to date. The list pages with numbered links, reading one page at a time from storage.

Filter by:

- text in the URL or recording id,
- view module,
- an event the session triggered, with suggestions from recorded event names,
- start time within the last hour, day or week,
- minimum number of events,
- sessions with an error, such as an error log, a failed query or a crash.

Filters are URL parameters, such as `/admin/replay?view=MyAppWeb.CheckoutLive&event=pay&within=24h&errors=1`, so a filtered list can be shared or bookmarked. `?tab=` lists the sessions of one browser tab. On phones, the filters other than search are behind a **Filters** button that counts the active ones. `PhoenixReplay.Recording.Filter` applies the same criteria in code.

## Player

The header names the view, the page and when the session started, with its duration and event count. When the session had errors, **"2 errors · jump to first"** takes you to the first one. **Copy link to 0:07** copies a link to the current moment: `/admin/replay/<id>?at=<index>` opens the player there.

The replayed page sits under a bar showing its URL at that moment. When the browser's viewport was recorded, the page renders at that size, fitted to the window or at 100% in a scrolling box, and the bar shows its size and scale.

Below it, play at 1×, 2×, 5× or 10×, step to the previous or next event, and see the time to the hundredth of a second. The timeline has a lane of markers per kind of event, LiveView, Telemetry and Logs, with errors larger and red. Click or drag it to seek, or focus it and use `←`, `→` and `Space`.

The panel beside it has three tabs:

- **Events** groups events by interaction: a mount, a user event, a navigation or a message, with the renders, component updates, [queries, requests and logs](telemetry-and-logs.md) it caused under it. Filter them by text, or hide a kind with its chip. The selected query, log or crash opens its details under it.
- **State** lists the assigns at that moment, marking the ones the selected event set. Open one to see its full value.
- **Visit** shows the device, the other sessions of the same browser tab, the page the user came from, and how the visit started: its campaign, referrer, landing page and kept headers.

When the session recorded the pointer, it is drawn over the replay: the cursor, moved between samples with a short trail, a ripple where it pressed, on the pressed element when the replayed page has it, and a fingertip for each touch. The replayed page scrolls as the user's did. **Pointer** in the frame's bar hides or shows them. See [Pointer, touches and scrolling](recording.md#pointer-touches-and-scrolling).

Each viewer drives a private frame, so several people can watch the same recording independently.

## Light and dark

The dashboard follows the system's light or dark appearance. To pin one, set `data-theme="light"` or `data-theme="dark"` on its `<html>`. It ships its own fonts, Geist and Geist Mono, and icons, so it looks the same in every app.

## The replay frame

The frame renders your views, so it needs your stylesheet. By default it loads `/assets/css/app.css` through your endpoint's `static_path/1`, which suits the stock esbuild and Tailwind setup.

If your assets are content-hashed by a bundler such as [Volt](https://hexdocs.pm/volt), render the frame in your own root layout:

```elixir
phoenix_replay "/replay", frame_layout: {MyAppWeb.Layouts, :root}
```

Interaction in the frame is ignored: recorded templates keep their `phx-click` bindings, but the frame does not act on them.

## Assets

The dashboard serves its own small script, stylesheet and fonts at content-hashed paths, and loads your application's own `phoenix` and `phoenix_live_view` client files, so the LiveView client always matches your server version. It needs nothing from your asset pipeline. Responses are public and cacheable, and work behind `:protect_from_forgery`.
