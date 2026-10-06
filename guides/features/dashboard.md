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

The header names the view, the page and when the session started, with its duration and event count. When the session had errors, **"2 errors · jump to first"** takes you to the first one. **Copy link to 0:07.25** copies a link to the current moment: `/admin/replay/<id>?at=<index>&t=<ms>` opens the player at that event, and at the time `t` in milliseconds when it falls between that event and the next.

The replayed page sits under a bar showing its URL at that moment. When the browser's viewport was recorded, the page renders at that size, and the bar shows its orientation, size and scale. That chip opens the **View** menu: fit the page to the window or show it at its actual size in a scrolling box, or **Rotate** it to the other orientation.

Below it, play at 1×, 2×, 5× or 10×, step to the previous or next event, and see the time to the hundredth of a second. The timeline has a lane of markers per kind of event, LiveView, Telemetry and Logs, with errors larger and red. Click or drag it to seek, or focus it and use `←`, `→` and `Space`.

The panel beside it has three tabs:

- **Events** groups events by interaction: a mount, a user event, a navigation or a message, with the renders, component updates, [queries, requests and logs](telemetry-and-logs.md) it caused under it. Filter them by text, or hide a kind with its chip. A pane under the list describes the current event in full: a user event's params, the assigns a render or component set, a navigation's URL, a query's SQL, duration and metadata, a log, a crash, client state or a viewport. Rows stay one line, so playback moves only the highlight. Pin the pane to keep an event's details while playback goes on, and drag the divider above it to resize it; the browser remembers the height.
- **State** lists the assigns at that moment, marking the ones the selected event set. Open one to see its full value.
- **Visit** shows the device, the other sessions of the same browser tab, the page the user came from, and how the visit started: its campaign, referrer, landing page and kept headers.

When the session recorded the pointer, it is drawn over the replay: the cursor, moved between samples with a short trail, a ripple where it pressed, on the pressed element when the replayed page has it, and a fingertip for each touch. The replayed page scrolls as the user's did, and stays there: the wheel does not move it. Turn off **Follow scroll** in the **View** menu to scroll it yourself. The cursor button in the frame's bar hides or shows them. See [Pointer, touches and scrolling](recording.md#pointer-touches-and-scrolling).

Each viewer drives a private frame, so several people can watch the same recording independently.

## Exporting videos

**Export video…** in the player's menu turns a saved recording into an MP4 of the replayed page and the pointer, for a bug report or a ticket. Its dialog chooses the range, from the start or the current moment to the end or another one; whether stretches without activity are shortened; whether the pointer is drawn; the orientation; and the size, frame rate and quality of the video. The defaults follow the configuration. A bar under the header shows its progress and, when it is done, links the video. **Cancel** stops it: a queued export never starts, and a running one closes its browser and stops encoding, leaving no files behind. Several viewers asking for the same recording share one export, and the video is kept for an hour.

The same export runs from the command line, with no server running:

```console
mix phoenix_replay.export <recording-id> --output checkout-bug.mp4 --from 12 --to 40 --fps 60
```

Its flags are the dialog's options: `--from` and `--to` in seconds, `--no-skip-idle`, `--no-pointer`, `--rotated`, `--size recorded|1x|half`, `--fps 15|30|60` and `--quality small|balanced|best`.

A recording holds no pixels, so an export replays it in a headless Chromium and films it, the way the player shows it: at the recorded viewport and pixel ratio, rotations included, with the cursor, touches, ripples and scrolling drawn over it. It films at 30 frames per second but screenshots only when the picture changes, and shortens stretches without activity to three seconds, so an export takes about as long as the activity it shows, not the whole session, and makes a small file. `ffmpeg` encodes it as H.264.

It needs three things on the machine that exports: [`playwright_ex`](https://hexdocs.pm/playwright_ex) with Playwright's Chromium, `ffmpeg`, and your endpoint named in the configuration:

```elixir
# mix.exs
{:playwright_ex, "~> 0.14"}

# config/config.exs
config :phoenix_replay, export: [endpoint: MyAppWeb.Endpoint]
```

```console
npm install playwright && npx playwright install chromium
```

Until all three are there, the menu has no **Export video**. The browser loads the replay from a private endpoint PhoenixReplay starts on 127.0.0.1 with the first export, behind a token, so your router needs no route for it and your login does not get in the way. Every other request the replayed page makes, such as its stylesheet, script, fonts or images, is passed to your endpoint in the same VM, as a request from 127.0.0.1; see [Privacy and Security](privacy-and-security.md#video-export). If the frame uses your own root layout, name it in `export: [frame_layout: ...]` too. Exports run one at a time under the application's supervision tree; see `PhoenixReplay.Export` for every option.

Only saved recordings are exported, not sessions still running. An export that would take more than `:max_shots` screenshots, 3,600 by default, fails with a message to choose a shorter range or a lower frame rate, since each screenshot is a file until the video is encoded. Videos left by a server that stopped are deleted when the next one starts, once they are older than `:ttl`.

## Light and dark

The dashboard follows the system's light or dark appearance. The sun and moon button in its header switches to the other one, and the browser remembers the choice. It ships its own fonts, Geist and Geist Mono, and icons, so it looks the same in every app.

SQL from `PhoenixReplay.Collector.Ecto`, metadata, and the assigns in the **State** tab are highlighted with [Lumis](https://hexdocs.pm/lumis) in Geist Mono, in colours that follow the theme. A custom collector gets its summary highlighted by setting `language: :sql` on the `PhoenixReplay.Collector.Captured` it returns. In the **State** tab, values the row shows whole are not expandable; longer ones open to their full, pretty-printed form.

## The replay frame

The frame renders your views, so it needs your stylesheet. By default it loads `/assets/css/app.css` through your endpoint's `static_path/1`, which suits the stock esbuild and Tailwind setup.

If your assets are content-hashed by a bundler such as [Volt](https://hexdocs.pm/volt), render the frame in your own root layout:

```elixir
phoenix_replay "/replay", frame_layout: {MyAppWeb.Layouts, :root}
```

Your root layout loads your own JavaScript in the frame. `replayRecorder` records nothing there, since the frame's LiveView is not recorded, but it is what puts recorded form values back into the replayed page, so keep it in the script your layout loads. Your hooks run in the frame too; a view whose live render depends on them can render without them in `replay_render/1`, see [Client state](recording.md#rendering-what-the-browser-did).

Interaction in the frame is ignored: recorded templates keep their `phx-click` bindings, but the frame does not act on them.

## Assets

The dashboard serves its own small script, stylesheet and fonts at content-hashed paths, and loads your application's own `phoenix` and `phoenix_live_view` client files, so the LiveView client always matches your server version. It needs nothing from your asset pipeline. Responses are public and cacheable, and work behind `:protect_from_forgery`.
