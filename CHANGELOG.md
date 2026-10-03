# Changelog

## Unreleased

### Added

- Telemetry collection. `:collect` lists `PhoenixReplay.Collector`s, whose events are recorded in the session of the process that emitted them, or of the LiveView that started it as a task, and listed in the player under the event that caused them. `PhoenixReplay.Collector.Ecto` records queries, `PhoenixReplay.Collector.Finch` records HTTP requests made with Finch or Req, and any event name records that event through `PhoenixReplay.Collector.Telemetry`.
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
- `PhoenixReplay.Recordings.fetch/3` redacts running sessions and reports progress; `PhoenixReplay.Recordings.live?/1` tells running sessions apart.

### Changed

- `[:phoenix_replay, :recording, :discarded]` metadata carries a `reason`: `:not_interactive` or `:not_sampled`.
- `PhoenixReplay.Storage.Ecto` stores `error_count`. Add the column to existing tables:

  ```elixir
  alter table(:phoenix_replay_recordings) do
    add :error_count, :integer, null: false, default: 0
  end
  ```

### Fixed

- LiveComponent state applied by `start_async`, `assign_async` and `stream_async` results is recorded. LiveView emits no telemetry for it yet, so `PhoenixReplay.Recorder.AsyncComponents` snapshots the component after such renders; see [phoenix_live_view#4463](https://github.com/phoenixframework/phoenix_live_view/pull/4463).
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
