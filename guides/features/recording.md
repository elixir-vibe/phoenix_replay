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
| `:viewport` | The browser's viewport changed: a resized window or a rotated phone |

The recording also keeps the view module, URL, sanitized params and session, and the start time. Everything passes through the configured sanitizer first; see [Privacy and Security](privacy-and-security.md).

## Browser and journey

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

- **the viewport** — width, height and pixel ratio when the LiveView connected. The player renders the replay at that size, keeping its aspect ratio: **Fit** scales it down until the whole viewport fits the window, centring a phone on a neutral stage, and **100%** shows it at true size in a scrolling box. A rotated phone eases into its new size, unless the viewer prefers reduced motion.
- **resizes** — a resized window or a rotated phone is recorded as a `:viewport` event when it settles, a fifth of a second after it stops changing, as long as `replayRecorder` runs; see [Pointer, touches and scrolling](#pointer-touches-and-scrolling). The viewport also travels with each click and key press, which catches changes without `replayRecorder`. Your `handle_event/3` receives the extra `"_replay"` param; recorded params leave it out.
- **the user agent** — shown in the player as, for example, "Safari on iOS".
- **the tab** — an id kept in the tab's `sessionStorage`. Navigating to another LiveView starts a new recording; the tab id ties them into one journey, and the player links the previous and next sessions of the tab.
- **the previous page** — the URL of the LiveView that live-navigated here (`client.navigated_from`).

### Visit context

Some context exists only on the HTTP requests of a visit, not on the LiveView socket: headers such as `Accept-Language`, the external `Referer` a visitor arrived from, and the campaign params of the page they landed on, which later LiveViews no longer see. `PhoenixReplay.Plug` keeps what `:context` asks for in the session, and every recording of the visit carries it:

```elixir
config :phoenix_replay,
  context: [
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
- **Attribution** is first-touch: the landing is kept for the whole visit. `attribution: :last` replaces it whenever a request carries tracked params, to see which campaign brought someone back.

A visit lasts as long as the session cookie. The plug rewrites the session only when the kept context changes, and does nothing until `:context` is configured; the installer adds it to the `:browser` pipeline. The player shows the campaign, the referrer's host and the landing page, with the params and headers under "Visit details".

Headers such as `x-forwarded-for` or `cf-connecting-ip` hold IP addresses, which are personal data in many jurisdictions; capture them only when you need them. Captured headers and the landing go through the [redactor](privacy-and-security.md#redacting-values) when a recording is saved.

The client module is `deps/phoenix_replay/priv/static/phoenix_replay.js`, with types; bundlers that resolve packages from `deps`, as Phoenix's esbuild and Volt setups do, import it as `"phoenix_replay"`.

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

The replay merges the state recorded up to the current moment into a reserved assign, `@phoenix_replay_state`: a map of each key to its merged fields, string keys throughout, empty before any report. A view whose live render depends on code in the browser defines `replay_render/1`, which the replay calls instead of `render/1` with the same assigns plus that one:

```elixir
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

Recording starts on every connected mount, but a session is saved only if the user interacted with it: it handled an event, in the view or a component, or navigated within the LiveView. Plain page views are discarded when the process exits.

`:keep` decides further, when the session ends. `keep: [rate: 0.1]` saves a tenth of interactive sessions, and `errors: true` or `slower_than: ms` always save sessions that hit an error or a slow query, even without interaction. See [Keeping the sessions that matter](telemetry-and-logs.md#keeping-the-sessions-that-matter).

## Sampling and limits

Record a share of sessions with `:sample_rate`, from `0.0` to `1.0`, and cap the events per session with `:max_events`. `:sample_rate` decides on mount; to decide once you know how the session went, record every session and use `:keep` instead. Set them globally:

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
- `[:phoenix_replay, :recording, :discarded]` with a `reason` of `:not_interactive` or `:not_sampled`,
- `[:phoenix_replay, :recording, :failed]` when saving gave up.

Each event fires after the session has left the buffer, so handlers see the finished state. `[:phoenix_replay, :collector, :exception]` reports a collector that raised; see [Telemetry and Logs](telemetry-and-logs.md#failures).

## Limitations

Replay reconstructs the assigns of LiveViews and LiveComponents. It does not reconstruct:

- streams and uploads, whose contents are not kept in assigns,
- what your JavaScript did with client state, such as rows a script filtered, unless the view renders it with `replay_render/1`; see [Client state](#client-state),
- focus, and `Phoenix.LiveView.JS` commands applied on the client.
