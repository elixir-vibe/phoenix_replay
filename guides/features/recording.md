# Recording

## What is recorded

`PhoenixReplay.Recorder` starts recording on the connected mount of every LiveView in a live session that lists it in `on_mount`:

```elixir
live_session :default, on_mount: [PhoenixReplay.Recorder] do
  live "/checkout", CheckoutLive
end
```

A recording is a list of `PhoenixReplay.Recording.Event` structs, each with a millisecond offset from the start of the session:

| Type | Data |
|---|---|
| `:mount` | Assigns when recording started |
| `:params` | `handle_params/3` params and URI |
| `:event` | `handle_event/3` name and params; `target: {module, id}` for events handled by a LiveComponent |
| `:info` | `handle_info/2` message tag, never the message itself |
| `:render` | Assigns changed by a render |
| `:component` | LiveComponent assigns changed by an update or event |
| `:component_destroyed` | A LiveComponent removed from the page |
| `:telemetry` | A telemetry event captured by a [collector](telemetry-and-logs.md) |
| `:log` | A log message, when [log collection](telemetry-and-logs.md#collecting-logs) is on |
| `:exit` | The formatted reason of a LiveView that exited abnormally |
| `:viewport` | The browser's viewport changed: a resized window, a rotated phone, or a switch to dark mode |
| `:pointer` | A batch of pointer moves, presses and scroll offsets, when [`:pointer`](#pointer-touches-and-scrolling) is on |
| `:state` | [Client state](#client-state) reported by the browser, form control values included |

The recording also keeps the view module, URL, sanitized params and session, and the start time. Everything passes through the configured sanitizer first; see [Privacy and Security](privacy-and-security.md).

## Browser and tab

A recording can also say which browser it came from and where the user went. The server cannot see these alone, so they are sent by the browser, and recordings simply leave them out when it does not send them.

```javascript
import { replayParams, replayMetadata } from "phoenix_replay"

const liveSocket = new LiveSocket("/live", Socket, {
  params: () => ({_csrf_token: csrfToken, ...replayParams()}),
  metadata: replayMetadata
})
```

```elixir
socket "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [:user_agent, session: @session_options]]
```

`mix igniter.install phoenix_replay` makes both changes for the setup Phoenix generates. With them, a recording's `PhoenixReplay.Recording.Client` holds:

- **the viewport** — width, height and pixel ratio when the LiveView connected. The player renders the replay at that size, keeping its aspect ratio: **Fit** scales it down until the whole viewport fits the window, centring a phone on a neutral stage, and **100%** shows it at true size in a scrolling box. When a phone turns, the player shows it turning, the way the screen's angle changed, unless the viewer prefers reduced motion.
- **the media settings** — the color scheme, reduced motion, contrast, the kind of pointer and whether it hovers, as the page's CSS saw them, with the viewport. The replayed page takes them, so its `prefers-color-scheme`, `prefers-reduced-motion`, `prefers-contrast`, `pointer` and `hover` rules, and Tailwind's `dark:`, `motion-reduce:`, `contrast-more:`, `pointer-coarse:` and `hover:` classes, show what the user saw: a phone session replays without hover styles. Stylesheets from another origin, and script that calls `matchMedia`, still see the viewer's. The Visit tab lists them.
- **resizes** — a resized window or a rotated phone is recorded as a `:viewport` event when it settles, a fifth of a second after it stops changing, as long as `replayRecorder` runs; see [Pointer, touches and scrolling](#pointer-touches-and-scrolling). The viewport also travels with each click and key press, which catches changes without `replayRecorder`. Your `handle_event/3` receives the extra `"_replay"` param; recorded params leave it out.
- **the user agent** — shown in the player as, for example, "Safari on iOS".
- **the tab** — an id kept in the tab's `sessionStorage`, shared by the recordings made in that tab; `?tab=` lists them. Navigating to another LiveView starts a new recording; the [visit](#visits) ties a person's recordings together, across tabs, and the player plays them in order.
- **the previous page** — the URL of the LiveView that live-navigated here (`client.navigated_from`).

### Visit context

Some context exists only on the HTTP requests of a visit, not on the LiveView socket: headers such as `Accept-Language`, the external `Referer` a visitor arrived from, and the campaign params of the page they landed on, which later LiveViews no longer see. `PhoenixReplay.Plug` keeps what the `:client` config asks for in the session, and every recording of the visit carries it:

```elixir
config :phoenix_replay,
  client: [
    headers: ["accept-language", "cf-ipcountry"],
    landing: [params: [:utm, :click_ids, "ref"], referrer: true]
  ]
```

```elixir
pipeline :browser do
  # after :fetch_session
  plug PhoenixReplay.Plug
end
```

- **`headers`** — an allowlist, refreshed on each request, each value cut to 256 characters. `cookie`, `authorization` and `proxy-authorization` are refused.
- **`landing`** — the visit's first `GET`: its path, time, tracked query params and `Referer`. `:utm` and `:click_ids` expand to the usual parameter names. The referrer loses its query string unless `referrer: :full`, since query strings often carry tokens.
- **Attribution** is first-touch: the landing is the visit's first page. `attribution: :last` moves it to the latest page that carries the visit's campaign params.

The plug rewrites the session only when the kept context changes; the installer adds it to the `:browser` pipeline. The player shows the campaign, the referrer's host and the landing page, with the params and headers under "Visit details".

### Visits

A visit is what web analytics call a session, and PhoenixReplay counts it the same way: it starts with a request, and ends after 30 minutes without one, or when a request arrives with campaign params that differ from its landing's. It spans the browser's tabs. `PhoenixReplay.Plug` gives each visit an id, kept in the session, and every recording made in it carries the id as `client.visit`. A recording is one LiveView; a visit is every recording between landing and leaving.

```elixir
config :phoenix_replay, client: [landing: [timeout: :timer.minutes(30)]]
```

The plug keeps the visit even without `:headers` or `:landing` configured. The time of the latest request is written once a minute has passed since the one kept, so a busy visit does not rewrite the session cookie on every request. Live navigation between LiveViews makes no request, so a visit that stays on LiveView pages for longer than the timeout ends at its next full page load. Recordings made without the plug, or before visits were kept, are each a visit of their own.

Headers such as `x-forwarded-for` or `cf-connecting-ip` hold IP addresses, which are personal data in many jurisdictions; capture them only when you need them. Captured headers and the landing go through the [redactor](privacy-and-security.md#redacting-values) when a recording is saved.

The client module is `deps/phoenix_replay/priv/static/phoenix_replay.js`, with types; bundlers that resolve packages from `deps`, as Phoenix's esbuild and Volt setups do, import it as `"phoenix_replay"`.

### Themes

A theme the user chooses in your app, rather than in their system, belongs on the server, like any setting, so recordings carry it: keep it in the session, give your LiveViews an `@theme` assign in an `on_mount` hook, and render it in your root layout, such as `<html data-theme={@theme}>`. A theme kept only in `localStorage` never reaches the server, so the replay cannot show it.

The replay needs nothing more. When the dashboard's `:frame_layout` is your root layout, the replay renders it again with each moment's assigns and gives the replayed page's `<html>` and `<body>` the attributes it renders then, as your layout would have live. The example app's `ExampleWeb.Theme` keeps a light, dark or system theme this way. A theme that follows the system is replayed from the recorded color scheme.

### Older recordings

Replay renders today's templates with the assigns recorded then. So each recording keeps which code it was made with: the release, the MD5 of its view and LiveComponents, and the versions of the dependencies that render, such as LiveView and component libraries. When any of them differs from the running code, the player notes "Code changed" and names what changed, and its Visit tab shows the release. Name your releases after your deploys, so the list's **Release** filter finds the sessions of one:

```elixir
# config/runtime.exs
config :phoenix_replay, release: System.get_env("GIT_SHA")
```

An assign a recording lacks needs nothing: it renders as `nil`, and the player notes it; see [Limitations](#limitations). An assign that changed shape since, such as a `:dark_mode` boolean that became a `:theme`, takes a migration, as a database's rows do: a module with a timestamp version, found among your app's modules with nothing to configure.

```elixir
defmodule MyAppWeb.ReplayMigrations.DarkModeToTheme do
  use PhoenixReplay.Migration, version: 20261007120000

  @impl true
  def up(MyAppWeb.TaskLive.Index, %{dark_mode: dark?} = assigns),
    do: Map.put_new(assigns, :theme, if(dark?, do: "dark", else: "light"))

  def up(_view_or_component, assigns), do: assigns
end
```

Each recording keeps the newest version it was made with, and replay applies the newer migrations, in order, to its view's and LiveComponents' assigns; the Visit tab lists them. See `PhoenixReplay.Migration`.

For a root layout whose `<html>` attributes come from something other than its assigns, a `PhoenixReplay.Replay` module, configured as `:replay`, gives them. How one LiveView renders in a replay is `PhoenixReplay.Replay.View`'s `replay_render/1`, below.

## Pointer, touches and scrolling

PhoenixReplay can also record where the pointer moved, what it pressed and how the page scrolled, and the player shows them over the replay. It is off by default. Turn it on globally or per live session:

```elixir
config :phoenix_replay, pointer: true

live_session :checkout, on_mount: [{PhoenixReplay.Recorder, pointer: true}] do
  # ...
end
```

and call `replayRecorder` from your JavaScript, after connecting the socket; `mix igniter.install phoenix_replay` adds it:

```js
import { replayParams, replayMetadata, replayRecorder } from "phoenix_replay"

liveSocket.connect()
replayRecorder(liveSocket)
```

`replayRecorder` records nothing until a recorded LiveView mounts and says what to record, and stops when the page navigates to another LiveView. It also records [client state](#client-state). The browser samples the pointer and the scroll offset, and sends them in batches over the LiveView socket as an event the recorder takes before your view sees it. Each setting has a default:

```elixir
config :phoenix_replay,
  pointer: [
    sample: 50,        # ms between recorded positions of a pointer
    scroll: 100,       # ms between recorded scroll offsets
    flush: 1_000,      # ms between the batches the browser sends
    max_points: 500,   # entries a batch holds before it is sent early
    limit: 3_600       # batches recorded per session
  ]
```

At the defaults, a moving pointer costs about 20 samples a second, a few hundred bytes, and a still one nothing. Mouse, pen and touch are recorded alike, each finger on its own and through scrolls and pinches, which the browser handles itself, and presses note the nearest element with an `id`, so the player can place them on it even if the replayed page lays out a little differently. Batches come from the browser, so the server drops anything malformed and caps each one at `:max_points`. They do not count towards `:max_events`, and pointer movement alone does not make a session interactive.

The fingers of a pinch are replayed, but not the zoom it causes: the page's pinch-zoom level is not recorded.

The player's clock runs to the end of the pointer track and of any client state, not only to the last LiveView event, so movement after the last event still plays.

## Client state

Replay re-renders your view with its recorded assigns, so on its own it cannot show what lives only in the browser. PhoenixReplay covers that in three tiers, from no code to a little:

1. **Form controls, automatically.** What users type and choose is recorded and put back into the replay, with no app code.
2. **Your own client state, with one function.** State your JavaScript holds, such as a draft or a client-side selection, is one `replayState` call.
3. **Libraries and JavaScript-driven effects.** A library reports with a DOM event, needing no dependency on PhoenixReplay, and a view renders what the browser did with `replay_render/1`.

All of it is recorded by default whenever `replayRecorder` runs; `state: false` turns it off, globally or per live session.

### Form controls

Text typed into inputs and textareas, checkboxes and radios, and options chosen in selects are recorded as users change them, whether or not the form has a `phx-change`, and the replay puts them back into the page after each render. A handler that validates without storing the value in assigns no longer replays as an empty box. Each control waits for a pause, `:debounce` milliseconds, so a typed sentence is one step on the player's timeline, not one per key.

Some controls are never read in the browser at all, so their values never leave it:

- password inputs, including one a "show password" toggle turned into text,
- hidden inputs, file inputs and buttons,
- fields whose `autocomplete` names a card (`cc-…`), a password (`current-password`, `new-password`) or a one-time code (`one-time-code`),
- anything inside an element with a `data-phx-replay-ignore` attribute:

```heex
<div data-phx-replay-ignore>
  <.input field={@form[:ssn]} label="Social security number" />
</div>
```

The rest are recorded under their `name`, so your `PhoenixReplay.Sanitizer` filters names such as `token` or `api_key` the way it filters event params. `state: [inputs: false]` turns form controls off and keeps the rest of client state.

The replay finds each control again by its `id`, or by its form's `id` and its own `name`; a checkbox also by its `value`, as checkboxes often share a name. A control with neither an `id` nor a form `id` and `name` is not recorded. Controls that a component renders under a changing `id` are not found again either.

**The replay shows values, not what your JavaScript did with them.** If a script filters a list as the user types into a search box, the replay puts the query back into the box, but the list still shows every row, which looks like a wrong replay. Render that effect yourself with `replay_render/1`; see [Rendering what the browser did](#rendering-what-the-browser-did).

### Your own client state

State your JavaScript holds is one call. `replayState` merges its fields into what was reported under the key before, so report only what changed:

```js
import { replayState } from "phoenix_replay"

replayState("draft", { body: editor.getText() })
```

Report whenever the state changes, without checking whether the page is recorded: PhoenixReplay keeps the latest state of each key, and a recording starts with the state as it is. State reported on one LiveView is forgotten when the page navigates to another.

### For library authors

A library that cannot import PhoenixReplay reports the same way with a DOM event on `window`, so it needs no dependency on it, in Elixir or in JavaScript:

```js
window.dispatchEvent(
  new CustomEvent("phx_replay:state", {
    detail: { key: "search", changes: { query: "shoes" } }
  })
)
```

`key` is a non-empty string naming the state, such as a component's id. `changes` is a JSON object of fields to merge into what was reported under `key` before, a shallow delta. It is copied when reported. Reports that are not a key and a JSON object within the limits are dropped. As with `replayState`, there is no need to know when recording starts.

A library that wants to know anyway can: `replayRecorder` dispatches `phx_replay:start` on `window` when the page's LiveView is recorded, with `{state: settings | null}` as its detail, and `phx_replay:stop` when recording ends, and `<html>` carries a `data-phx-replay` attribute holding the same detail as JSON while recording.

### Rendering what the browser did

The replay merges the state recorded up to the current moment into a reserved assign, `@phoenix_replay_state`: a map of each key to its merged fields, string keys throughout, empty before any report. A view whose live render depends on code in the browser defines `replay_render/1`, the optional callback of `PhoenixReplay.Replay.View`, which the replay calls instead of `render/1` with the same assigns plus that one:

```elixir
@behaviour PhoenixReplay.Replay.View

@impl PhoenixReplay.Replay.View
def replay_render(assigns) do
  query = get_in(assigns.phoenix_replay_state, ["search", "query"])

  assigns
  |> assign(:visible, Enum.filter(assigns.tasks, &(query in [nil, ""] or &1.title =~ query)))
  |> render_list()
end
```

It is rendered in full on every step, so values you derive in it with `assign/3` always show; `@` access in `~H` works as usual. Each report is a step on the player's timeline, in a lane of its own, so seeking to a moment shows the state as it was then. Form control values are under the `"phx_replay:inputs"` key, `%{selector => %{name => value}}`. Don't name an assign of your own `:phoenix_replay_state`.

### Limits

```elixir
config :phoenix_replay,
  state: [
    inputs: true,            # record form controls
    debounce: 300,           # ms a control must stay unchanged before it is recorded
    flush: 1_000,            # ms between the batches the browser sends
    max_entries: 200,        # entries a batch holds before it is sent early
    max_key: 64,             # bytes a key may have
    max_entry_bytes: 8_192,  # JSON size of one entry's changes; larger ones are dropped
    max_bytes: 65_536,       # JSON size a batch holds before it is sent early
    limit: 3_600             # batches recorded per session
  ]
```

Client state goes through your `PhoenixReplay.Sanitizer`'s `sanitize_params/1` when it arrives and through your `PhoenixReplay.Redactor` when the session is saved. It does not count towards `:max_events`. A changed form control makes a session interactive, as does a change to a key reported before; the first report of any other key, the state the page started with, does not.

PhoenixReplay does not record focus, or `Phoenix.LiveView.JS` commands applied on the client, which the replay does not re-run.

## Which sessions are kept

Recording starts on every connected mount, but a recording is saved only if its [visit](#visits) is kept. A visit is kept once any of its recordings would be kept on its own: the user interacted with it, by handling an event, in the view or a component, or by navigating within the LiveView, or it matched `:keep`. Then all of the visit's recordings are saved, pages the user only read included, so a visit replays from landing to leaving. A visit whose recordings are all plain page views is discarded whole.

`:keep` decides further. `keep: [rate: 0.1]` saves a tenth of visits with interaction, and `errors: true`, `marks: true` or `slower_than: ms` always save visits that hit an error, a mark or a slow query, even without interaction. See [Keeping the sessions that matter](telemetry-and-logs.md#keeping-the-sessions-that-matter).

A recording that ends before its visit is kept waits for the decision, its events held in memory: it is saved when another recording of the visit is kept, and discarded when the visit ends. For this, a visit ends when none of its recordings is running and none has started for the visit's timeout, 30 minutes by default. Held recordings count towards `:max_memory`, and while the buffer is over it, the recordings held for the visit idle longest are discarded, with the reason `:max_memory`. The decision is kept by the node that recorded the pages; a visit whose pages reach several nodes is kept on each by the pages it recorded there.

Retention and the per-collector `:limit`s apply to each recording, not to the visit.

## Sampling and limits

Record a share of visits with `:sample_rate`, from `0.0` to `1.0`, and cap the events per recording with `:max_events`. `:sample_rate` decides on mount, from a draw the visit makes once, so a visit's recordings are recorded or not together; a live session's own `:sample_rate` applies to the same draw. To decide once you know how the visit went, record every visit and use `:keep` instead. Set them globally:

```elixir
config :phoenix_replay,
  sample_rate: 0.25,
  max_events: 10_000
```

or per live session, which overrides the global values:

```elixir
live_session :checkout,
  on_mount: [{PhoenixReplay.Recorder, sample_rate: 1.0, max_events: 2_000}] do
  live "/checkout", CheckoutLive
end
```

Per-session options accept `:sample_rate`, `:keep`, `:max_events`, `:sanitizer` and `:redact`. Once a session reaches `:max_events`, further LiveView events are dropped and the recording is kept as it is. Collected telemetry and logs have their own limits.

`:max_memory` caps the buffer of sessions in progress, in bytes. While it is exceeded, new sessions are not recorded.

## Telemetry

`PhoenixReplay.Telemetry` emits an event when a session is finalized:

- `[:phoenix_replay, :recording, :persisted]` with `event_count` and `duration_ms` measurements,
- `[:phoenix_replay, :recording, :discarded]` with a `reason` of `:not_interactive`, `:not_sampled`, or `:max_memory` for a recording [held for its visit](#which-sessions-are-kept) until the buffer needed the room,
- `[:phoenix_replay, :recording, :failed]` when saving gave up.

Each event fires after the session has left the buffer, so handlers see the finished state. `[:phoenix_replay, :collector, :exception]` reports a collector that raised; see [Telemetry and Logs](telemetry-and-logs.md#failures).

## Limitations

Replay reconstructs the assigns of LiveViews and LiveComponents. It does not reconstruct:

- streams and uploads, whose contents are not kept in assigns,
- what your JavaScript did with client state, such as rows a script filtered, unless the view renders it with `replay_render/1`; see [Client state](#client-state),
- focus, and `Phoenix.LiveView.JS` commands applied on the client.

Replay renders today's templates with the assigns recorded then. When a template reads an assign a recording lacks, such as one added after the session was recorded, the replay renders it as `nil`, which most templates take as unset, and the player notes "Not in recording: @name". A template that cannot take `nil` there still shows a placeholder for that moment.

Recordings name modules as atoms: the view, its LiveComponents, and structs in assigns. They are read back only with atoms the node knows, so a recording that names a module deleted or renamed since can no longer be read; rename a LiveView or LiveComponent only once its recordings no longer matter. Which code each recording was made with is kept by name, so that much stays readable.
