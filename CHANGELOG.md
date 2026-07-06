# Changelog

## Unreleased

### Breaking changes

- Store ETF recordings as Erlang's built-in compressed ETF (`:erlang.term_to_binary(term, compressed: 6)`) instead of gzip-wrapping serializer output.
- File storage now writes `.etf` and `.json` files instead of `.etf.gz` and `.json.gz`; existing gzip-wrapped recordings are not supported by this version.
- Ecto storage now stores serializer output directly without a gzip wrapper; existing gzip-wrapped database rows must be migrated or discarded.

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
