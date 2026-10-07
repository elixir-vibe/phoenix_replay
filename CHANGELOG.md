# Changelog

## Unreleased

Pointer, touch and form recording, marks, video export, and a richer player and recording list.

### Upgrading

- Ecto storage: run migration version 3, `PhoenixReplay.Storage.Ecto.Migration.up(from: 2, version: 3)`. Saving and listing fail until it runs.
- Renamed modules: `PhoenixReplay.Recordings` is now `PhoenixReplay.Catalog`, `Recordings.Filter` is `PhoenixReplay.Recording.Filter`, `Recordings.Retention` is `PhoenixReplay.Storage.Retention`, `Recording.Keep` is `PhoenixReplay.Session.TailSampling`, and `Recordings.complete/3` is `PhoenixReplay.Session.Finalizer.complete/3`.
- `PhoenixReplay.Recording.Summary`'s `source` holds only the source, with `medium` and `campaign` beside it. A recording's `client` is a `PhoenixReplay.Recording.Client` struct, whose `referer` is now `navigated_from`. Saved recordings are upgraded when read.
- Custom storage backends: the optional `facets/1` callback is replaced by `values/4`, and `PhoenixReplay.Storage.File.query/3` is gone.
- `:flush`, `:pointer`, `:logs` and `:landing` set on a live session now merge into the global configuration instead of replacing it.
- The `:context` option is now `:client`, as recordings call it. `:context` still works, with a deprecation warning.

### Added

- Pointer, touch and scroll recording with `pointer: true`. Call `replayRecorder(liveSocket)` in your client code; the installer adds it.
- Form inputs are recorded and replayed with no app code. Passwords, payment and one-time-code fields are never read; `state: [inputs: false]` turns it off.
- Client-only state: report it with `replayState(key, changes)`, and the replay renders it from `@phoenix_replay_state`, or with a view's `replay_render/1`, from `PhoenixReplay.Replay.View`.
- Marks: collect a telemetry event with `mark: true` to mark a moment such as a signup or a checkout. Marks get a timeline lane, a header menu and a list filter, and `keep: [marks: true]` saves every session that reaches one.
- `phx_replay:start` and `phx_replay:stop` window events, and a `data-phx-replay` attribute on `<html>`, tell browser code when a page is recorded.
- The player draws the recorded cursor, taps and touches over the replay, and scrolls the page as the user did.
- The player's **View** menu: Fit, Actual size, Rotate, and Follow scroll. **Rotate** turns the shown device to look at it the other way round; when the user turned their phone, the replay shows it turning.
- The recorder captures the user's color scheme, reduced motion, contrast, pointer type and hover with the viewport, and the replay applies them to the page's media rules, so a dark-mode or phone session looks as it did, `dark:` and `pointer-coarse:` styles included, and a phone session shows no desktop scrollbar. The Visit tab lists them, and `client: [media: …]` keeps fewer.
- The replay renders your root layout again with each moment's assigns, so `<html>` and `<body>` attributes that follow them, such as a theme the server keeps, change as the session plays. A `PhoenixReplay.Replay` module, configured as `:replay`, adapts the assigns older recordings hold, and covers layouts that read something else. See the recording guide's "Themes" and "Older recordings".
- The **State** tab shows what each event changed, such as `tasks[id: 2].done: false → true`.
- A details pane for the playing or pinned event, with telemetry measurements. Slow queries and calls stand out.
- SQL, assigns and metadata are syntax-highlighted.
- Keyboard shortcuts in the player; `?` lists them.
- A light and dark theme switch.
- The recording list filters by source, medium and campaign, device, browser, duration and mark, as chips that show how many sessions have each value.
- A chart of sessions over time above the list, with errors in red; click a bar to narrow the list to it.
- List rows show the device, browser, where the visit came from and the marks it reached.
- A time window or a calendar date range for the list. Dashboard times are in the viewer's time zone.
- Video export: turn a recording into an MP4 from the player's menu or with `mix phoenix_replay.export <id>`. Set `export: [endpoint: MyAppWeb.Endpoint]`; it needs `ffmpeg` and the optional `playwright_ex` and `muontrap` dependencies. See `PhoenixReplay.Export`.
- `PhoenixReplay.Export.Queue.Oban` runs exports in your Oban queue, so they survive restarts and deploys.
- Each recording keeps which code it was made with: the release, set with `:release` or your app's version, the MD5 of its view and LiveComponents, and the versions of the dependencies that render. The player notes "Code changed" when they differ from the running code, and the list filters by **Release**.
- `PhoenixReplay.Trace`, `mix phoenix_replay.list` and `mix phoenix_replay.show` read recordings as plain data, for IEx, tests and coding agents. Two agent skills ship in the package's `skills` directory.
- Optional `child_spec/1` and `histogram/4` callbacks for storage backends.

### Changed

- The default sanitizer also filters card numbers, CVVs, social security numbers, PINs and one-time codes.
- LiveView internals such as `:__changed__`, `:uploads` and `:streams` are dropped from recorded assigns before your sanitizer sees them.
- Resizes and rotations are recorded as soon as they settle, not with the next click.
- Menus and tooltips are no longer cut off by scrolling panels.
- [Lumis](https://hexdocs.pm/lumis) is a new dependency, for syntax highlighting.

### Fixed

- Scrubbing to the start no longer shows "Could not render".
- Scrubbing between events and pausing keep the moment you chose instead of jumping back to the previous event.
- **Copy link** links the exact moment the clock shows.
- Switching from 100% back to Fit after scrolling no longer shifts the page out of view.
- Collected details, such as SQL, no longer break words mid-way.
- A recording made before a template began to read an assign replays with it unset, and the player notes which, rather than showing "Could not render".
- An event that one of your `on_mount` hooks handles and halts is recorded too, wherever the hook sits: events are recorded from LiveView's telemetry.
- On a wide screen the player fits the window, so the page no longer scrolls; the replay scales to the space left.
- The Visit tab shows landing parameters beside their names, not on a line below.
- Running `iex -S mix` or a Mix task next to a running server no longer marks the server's sessions as interrupted.
- A save that fails, such as while the database is down, is retried instead of losing the recording.
- A LiveComponent that fails to record is reported through `[:phoenix_replay, :collector, :exception]` telemetry instead of a log line.

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
