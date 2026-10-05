# Changelog

## Unreleased

### Added

- Pointer, touch and scroll recording, off by default. `:pointer` turns it on, globally or per live session, with every interval and cap configurable: `:sample`, `:scroll`, `:flush`, `:max_points` and `:limit`. The client module's new `replayRecorder(liveSocket)` records only while a recorded LiveView asks for it, keeps recording through patches and events pushed with page loading, and sends batches over the LiveView socket as an event the recorder halts before the view sees it. The installer wires it.
- The player draws the pointer over the replay: the cursor with a short trail, a ripple for each press, placed on the pressed element when the replay has it, and a fingertip for each touch, and it scrolls the replayed page as recorded. **Pointer** in the frame's bar toggles them.
- Form controls are recorded and replayed with no app code: what users type and choose in inputs, textareas, checkboxes, radios and selects, with or without `phx-change`. Each control waits for a pause (`state: [debounce: 300]`) so typing is one step on the timeline, and the replay puts the values back after each render. Passwords, hidden and file inputs, `autocomplete="cc-…"` fields and anything inside `data-phx-replay-ignore` are never read in the browser; the rest are recorded under their names, so the sanitizer filters them as it filters event params. `state: [inputs: false]` turns this off.
- Client state: app code reports state the server never sees with `replayState(key, changes)` from the client module, and libraries that cannot import PhoenixReplay with a `phx_replay:state` window event. The client keeps the latest state of each key, so a recording starts with the state as it is and reporters need not know when it starts. The server validates, sanitizes and caps it; `:state` configures the limits, and it is on by default.
- `phx_replay:start` and `phx_replay:stop` window events, and a `data-phx-replay` attribute on `<html>`, tell code in the browser when the page's LiveView is recorded.
- The replay merges client state up to the current moment into the reserved `@phoenix_replay_state` assign, and calls a view's optional `replay_render/1` instead of `render/1` when it defines one. The player shows client state as steps in a lane of their own.
- A button in the dashboard's header switches between the light and dark themes, overriding the system's appearance; the browser remembers the choice.
- SQL, collected metadata and the assigns in the player's **State** tab are highlighted with Lumis in a monospace font, in colours that follow the theme. Rows in the event list show the action in the interface's font and what it acted on in monospace, coloured the same way: event params, message tags, assign names, components, URLs, client state and collected SQL. Log messages stay prose. `PhoenixReplay.Collector.Captured` has a `:language` field, `:sql` for `PhoenixReplay.Collector.Ecto`, that turns highlighting on for a collector's summary.
- In the **State** tab, only values their row cannot show whole are expandable.
- The player shows the pointer overlay's toggle as a switch, and covers the replay with a loader until its frame has connected, instead of a blank box.
- The **State** tab shows what the current event changed inside each assign, such as `tasks[id: 2].done: false → true`, matching list items by `id`, and an expanded assign marks its removed and added lines.
- `PhoenixReplay.Storage` has an optional `child_spec/1` callback for a process the backend needs, which the application starts. File storage starts its summary index this way; a file storage used while its index is not running, such as one configured by hand next to another backend, reads summaries from disk.

### Changed

- Modules are renamed so no two differ only by a suffix or share a name across namespaces. `PhoenixReplay.Recordings` is now `PhoenixReplay.Catalog`, `PhoenixReplay.Recordings.Filter` is `PhoenixReplay.Recording.Filter`, which storage backends that implement `query/3` use, `PhoenixReplay.Recordings.Retention` is `PhoenixReplay.Storage.Retention`, and `PhoenixReplay.Recording.Keep` is `PhoenixReplay.Session.TailSampling`. Completing a running session's recording moved from `Recordings.complete/3` to `PhoenixReplay.Session.Finalizer.complete/3`. The `:retention` and `:keep` options are unchanged.
- A recording's `client` is a `PhoenixReplay.Recording.Client` struct, and its landing a `PhoenixReplay.Recording.Client.Landing`. The URL of the LiveView that live-navigated to the session is `navigated_from`, formerly `referer`, so it no longer reads like the landing's HTTP `referrer`. Recordings stored by earlier versions are brought up to date when read.
- Overriding `:flush`, `:pointer`, `:logs` or `:landing` in a live session merges the override into the global configuration, as the other options already did, instead of starting from the defaults. `nil` and `false` switch any of these options off; `true` switches one on with the global configuration or the defaults.
- LiveView internals (`:__changed__`, `:uploads`, `:streams`, and a component's `:myself` and `:flash`) are left out of recorded assigns before the sanitizer runs, so a custom `PhoenixReplay.Sanitizer` no longer has to drop them.
- `PhoenixReplay.Storage.File.query/3` is gone; the storage facade pages file storage from `list/1`.

### Fixed

- Scrubbing to a moment between two events keeps that moment, instead of snapping back to the earlier event, and the thumb stays under the pointer while dragging.
- Pausing the player keeps the time playback reached between two events, instead of jumping back to the last one, and resuming or changing speed plays on from there.
- Switching the player from 100% back to Fit after scrolling the replay eases from the scrolled view into the fitted one, instead of leaving the page shifted out of view.
- Collected details no longer break words mid-way, such as SQL table names.
- A LiveComponent whose recording fails, such as with a raising sanitizer, is reported with `[:phoenix_replay, :collector, :exception]`, as collectors are, instead of logged.
- A save that raised, such as an Ecto save while the database is down, is retried like one that returned an error, rather than dropping the recording.
- `[:phoenix_replay, :recording, :persisted]` and `:recovered` count events without pointer batches, as the summary does.

## 0.5.1 - 2026-10-04

The rest of the dashboard redesign.

### Added

- The player's kind filters have an **Errors** chip that narrows the event list to the events that report an error, under the interaction that caused them.
- `/` focuses the search on the recording list and in the player.
- On phones, the recording list has All, With errors and Last 24 h quick filters under the search.
- The replay is labelled "Replayed from recorded assigns", since it re-renders the view rather than capturing the screen.

### Changed

- Text search in the recording list also matches event names. `PhoenixReplay.Storage.Ecto` checks it after the SQL criteria, as it does for the event filter, since event names are stored encoded; it no longer uses an SQL fragment.
- Errors on the timeline are larger, with a soft ring.

## 0.5.0 - 2026-10-04

### Added

- Telemetry collection. `:collect` lists `PhoenixReplay.Collector`s, whose events are recorded in the session of the process that emitted them, or of the LiveView that started it as a task, and listed in the player under the event that caused them. `PhoenixReplay.Collector.Ecto` records queries, `PhoenixReplay.Collector.Finch` records HTTP requests made with Finch or Req, and any event name records that event through `PhoenixReplay.Collector.Generic`.
- Log collection with `:logs`, which records Logger messages in the same way.
- Tail sampling with `:keep`: `rate` saves a share of sessions when they end, and `errors: true` and `slower_than: ms` always save sessions with an error or a slow collected event. LiveViews that exit abnormally record an `:exit` event.
- `:max_memory` stops recording new sessions while the buffer is larger.
- Running sessions are written to storage in chunks, as `:flush` configures (by default every 200 events or 5 seconds), once `:keep` decides to keep them. Their events leave memory, a crash of the node loses at most the last chunk, and the next start saves what was written as an interrupted recording, emitting `[:phoenix_replay, :recording, :recovered]`. `PhoenixReplay.Storage.File` implements the new optional `append/3`, `fetch_partial/2` and `partials/1` callbacks, and takes `sync: true` to sync each chunk.
- File storage writes recordings and summaries to a temporary file, syncs and renames them into place.
- The application waits for recordings being saved or written when it stops.
- `:redact` takes a `PhoenixReplay.Redactor`, which masks sensitive values in every recorded string when a session is saved, in a background task, and when the dashboard opens a running session. A list of regexes uses `PhoenixReplay.Redactor.Patterns`; `PhoenixReplay.Redactor.Obscura` detects personal data with the optional [Obscura](https://hexdocs.pm/obscura) dependency. A failing redactor stops the save rather than storing unredacted data.
- The player redacts running sessions with `start_async/3` and shows progress, and hands the result to its frame.
- `[:phoenix_replay, :collector, :exception]` reports collectors that raised.
- `PhoenixReplay.Recording.Summary` counts `error_count`, the dashboard marks errors and filters sessions with `?errors=1`, and the player hides events by kind.
- `on_mount: {PhoenixReplay.Recorder, opts}` accepts `:keep` and `:redact`.
- Recordings can carry the browser's viewport, user agent, tab and the URL the user came from, sent by the new client module (`import { replayParams, replayMetadata } from "phoenix_replay"`) and `:user_agent` in the LiveView socket's `connect_info`. Resizes are recorded as `:viewport` events. The player renders the replay at the recorded viewport, keeping its aspect ratio — fitted to the window or at 100% in a scrolling box — names the browser, and links the sessions of one tab; the dashboard filters them with `?tab=`. The installer wires up the client and the user agent.
- `PhoenixReplay.Plug` and the `:context` option keep request context for a visit in the session, so every recording carries it: an allowlist of `:headers`, and the `:landing` request with its path, campaign params (`:utm` and `:click_ids` presets) and referrer, first-touch or last-touch. The player shows the campaign, referrer and landing page. The installer adds the plug to the `:browser` pipeline.
- `PhoenixReplay.Recordings.fetch/3` redacts running sessions and reports progress; `PhoenixReplay.Recordings.live?/1` tells running sessions apart.
- The dashboard follows the system's dark mode, or `data-theme="light"` / `"dark"` on its `<html>`. It ships the Geist and Geist Mono fonts and Lucide icons through [`phoenix_iconify`](https://hexdocs.pm/phoenix_iconify), so it needs nothing from the host app.
- The player follows the redesign: a header with the recording's page, time, a jump to its first error and a link to the current moment (`?at=<index>` opens the player there), the replay under a URL bar, playback controls with a timeline lane per kind of event, and a side panel. Its Events tab groups events by interaction, filters them by text and kind, and opens a query's, log's or exit's details under it; State shows the assigns at that moment, marking the ones it set; Visit shows the device, browser tab, referrer and landing.
- `PhoenixReplay.Recording.Summary` carries the session's `viewport`, `device` (such as "Mobile Safari 18 on iOS") and `source` (the landing's campaign or referring host), and the recording list shows them. Devices are named with [`ua_parser`](https://hexdocs.pm/ua_parser), a new dependency. On phones, the list's filters sit behind a Filters button.
- The recording list keeps its place while sessions end: saved recordings are listed as of when the list was opened or its filter changed, and newer ones are counted in a "3 new recordings · Show" banner instead of shifting the rows.
- The recording list reads one page at a time through the new optional `PhoenixReplay.Storage` callbacks `query/3` (filters, offset, limit, `:since` and `:until`, with a total) and `facets/1` (views and event names to suggest). `PhoenixReplay.Storage.Ecto` pages in SQL, and `PhoenixReplay.Storage.File` keeps summaries in an ETS index, reading only the summary files it has not seen. Backends without them are paged from `list/1` as before.
- The recording list shows running sessions under "Live now" and saved ones in a table with relative start times, duration, events and errors. A whole row opens its recording, and it pages with numbered links.

### Changed

- Internal modules are grouped by role: `PhoenixReplay.Capture.*` observes LiveViews, `PhoenixReplay.Session.*` follows a running recording until it is stored. `PhoenixReplay.Recorder` is only the `on_mount` hook. `PhoenixReplay.Retention` is now `PhoenixReplay.Recordings.Retention`; the `:retention` option is unchanged.
- `[:phoenix_replay, :recording, :discarded]` metadata carries a `reason`: `:not_interactive` or `:not_sampled`.
- `PhoenixReplay.Storage.Ecto` stores `error_count`, `tab`, `viewport`, `device`, `source` and `saved_at`. The table now comes from `PhoenixReplay.Storage.Ecto.Migration`, which needs `ecto_sql`, now an optional dependency; upgrade one made by 0.4 with a new migration:

  ```elixir
  def up, do: PhoenixReplay.Storage.Ecto.Migration.up(from: 1, version: 2)
  def down, do: PhoenixReplay.Storage.Ecto.Migration.down(from: 1, version: 2)
  ```

### Fixed

- LiveComponent state applied by `start_async`, `assign_async` and `stream_async` results is recorded. LiveView emits no telemetry for it yet, so `PhoenixReplay.Capture.AsyncResults` snapshots the component after such renders; see [phoenix_live_view#4463](https://github.com/phoenixframework/phoenix_live_view/pull/4463).
- LiveViews not mounted at the router, such as `live_render/3` children, are recorded instead of crashing.

## 0.4.0 - 2026-10-03

### Added

- LiveComponent state is recorded and replayed with no changes to components. Recording uses LiveView's component telemetry; replay renders each component's template with its recorded assigns. Events handled by components are recorded, so sessions with only component interaction are kept.
- `mix igniter.install phoenix_replay` mounts the dashboard behind `:dev_routes`, turns recording off in tests, imports the formatter settings and ignores local recordings.
- `:sample_rate` records a share of sessions.
- `on_mount: {PhoenixReplay.Recorder, opts}` sets `:sample_rate`, `:max_events` and `:sanitizer` per live session.
- Dashboard filters by view, URL or id, triggered event, age and event count, kept in the URL. `PhoenixReplay.Recordings.Filter` applies the same criteria in code.
- `PhoenixReplay.Recording.Summary` lists the session's distinct `event_names`. Recordings saved by 0.3.0 have none, so event filters do not match them.
- Guides for getting started, recording, LiveComponents, the dashboard, storage, privacy and security, and testing, plus a configuration cheatsheet.

### Changed

- `PhoenixReplay.Telemetry` events fire after the session has left the buffer, so handlers observe the finished state.

### Fixed

- The recorder monitor no longer crashes on an unexpected `:DOWN` message.
- Stored structs decode with defaults for fields added after they were saved.

### Upgrading

- `PhoenixReplay.Storage.Ecto` needs an `event_names` column: `add :event_names, :binary, null: false, default: <<131, 106>>`, the encoding of an empty list.
- Add `config :phoenix_replay, sample_rate: 0.0` to `config/test.exs` unless your tests should record sessions.

## 0.3.0

A rewrite for a cleaner architecture. Configuration, storage formats and public modules changed; recordings saved by 0.2 are not readable.

### Breaking

- Configuration is validated by `PhoenixReplay.Config`. `:storage` takes `{module, opts}` and replaces `:storage_opts`; retention and persistence options moved under `:retention` and `:persist`.
- `PhoenixReplay.Store`, `PhoenixReplay.Persistence` and the old `PhoenixReplay.Recordings` are replaced by `PhoenixReplay.Recordings`, `PhoenixReplay.Recorder.Buffer`, `PhoenixReplay.Recorder.Monitor`, `PhoenixReplay.Recorder.Persister` and `PhoenixReplay.Retention`.
- Events are `PhoenixReplay.Recording.Event` structs; listings return `PhoenixReplay.Recording.Summary` structs.
- The `:authorize` function config is replaced by the `PhoenixReplay.Authorization` behaviour, passed to the router macro.
- Storage backends implement `save/2`, `fetch/2`, `list/1`, `delete/2` and `clear/1`; `init/1` and the optional callbacks are gone. JSON storage and legacy file formats are removed.
- Sanitizers implement `sanitize_assigns/1` and `sanitize_params/1`; `sanitize_delta/2` is removed. Sensitive values are replaced with `"[FILTERED]"` instead of dropped.
- `PhoenixReplay.Recorder.attach/3` is removed; use the `on_mount` hook.
- Requires Elixir 1.18 and Phoenix LiveView 1.1.

### Fixes

- Deleting and clearing recordings respect authorization.
- Viewers of the same recording no longer drive each other's playback.
- Recordings that fail to save no longer leak buffered events.
- In-progress recordings survive worker restarts.
- One unreadable file no longer hides every recording.
- The replay frame catches template errors instead of crashing.
- Missing recordings respond with 404 under the dashboard path.

### Improvements

- Dashboard ships its own CSS and a TypeScript player, and loads the host's own Phoenix and LiveView clients.
- Server-driven playback with a keyboard-accessible timeline.
- Recorded flash messages are replayed.
- Listing reads summaries without decoding recordings.
- Telemetry events for saved, discarded and failed recordings.
- The dashboard refreshes over PubSub instead of polling.


## 0.2.0

### Improvements

- Extract replay player JavaScript into packaged static assets
- Add dashboard pagination, delete controls, and clear-all controls
- Add recording retention cleanup by count and age
- Retry async persistence failures before logging final failure
- Add Ecto storage integration coverage and GitHub Actions CI
- Auto-scroll events panel to keep the active event visible during playback
- Filter idle sessions (no user events) from the dashboard index
- `Store.list_active/0` — list active recordings without private LiveView debug APIs
- `Recorder.attach/3` now accepts optional `params` and `session` arguments

## 0.1.0 — 2026-03-10

- Initial release
