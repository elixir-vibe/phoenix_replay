# Changelog

## Unreleased

### Added

- `:sample_rate` records a share of sessions.
- `on_mount: {PhoenixReplay.Recorder, opts}` sets `:sample_rate`, `:max_events` and `:sanitizer` per live session.

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
