---
name: phoenix-replay-setup
description: Sets up PhoenixReplay, session recording and replay for Phoenix LiveView, in a Phoenix app. Load when asked to add session replay or recording to a Phoenix or LiveView project, when mix.exs gains :phoenix_replay, or when a router, live_session or config mentions PhoenixReplay.Recorder, phoenix_replay or PhoenixReplay.Plug.
---

# Setting up PhoenixReplay

PhoenixReplay records each LiveView session as a timeline of events and assigns, and replays it by rendering the view's own template with the recorded assigns. Recording happens on the server; a small client module adds form controls, the pointer and the browser's viewport.

## 1. Install

Prefer the Igniter installer. It is idempotent and prints what it could not do:

```bash
mix igniter.install phoenix_replay
```

It:

- imports `:phoenix_replay` in `.formatter.exs`
- mounts the dashboard at `/dev/replay` behind `:dev_routes`, and enables `:dev_routes` in `config/dev.exs`
- turns recording off in `config/test.exs` (`sample_rate: 0.0`)
- ignores `priv/replay_recordings/` in `.gitignore`
- adds `PhoenixReplay.Plug` to the `:browser` pipeline
- adds `:user_agent` to the LiveView socket's `connect_info`
- wires the client module into `assets/js/app.js` (or `app.ts`): `replayParams` and `replayMetadata` in the `LiveSocket` options, and `replayRecorder(liveSocket)` after `connect()`

Without Igniter, or when the installer says it left something alone (a custom `LiveSocket` setup, no `:browser` pipeline), do those steps by hand; `guides/introduction/getting-started.md` in the package shows each.

## 2. Choose what to record

Nothing is recorded until a live session has the recorder. Add it to the sessions whose pages should be replayable:

```elixir
live_session :default, on_mount: [PhoenixReplay.Recorder] do
  live "/", HomeLive
  live "/checkout", CheckoutLive
end
```

Put it after the app's own hooks, such as authentication: a visit they halt is then never recorded, and the recorded mount includes what they assigned. Per-session options override the global configuration: `{PhoenixReplay.Recorder, sample_rate: 0.1, pointer: true}`.

## 3. Configure

Everything is optional; defaults record every session to files under `priv/replay_recordings`. Add only what the user asks for, in `config/config.exs`:

```elixir
config :phoenix_replay,
  # Queries and logs alongside LiveView events.
  collect: [{PhoenixReplay.Collector.Ecto, repo: MyApp.Repo}],
  logs: [level: :info],
  # Save a share of sessions, but always those with an error.
  keep: [rate: 0.1, errors: true],
  # The pointer, touches and scrolling, drawn over the replay.
  pointer: true,
  # Delete recordings after a week.
  retention: [max_age: :timer.hours(24 * 7)]
```

- Production storage: `storage: {PhoenixReplay.Storage.Ecto, repo: MyApp.Repo}`, with a migration whose `up` calls `PhoenixReplay.Storage.Ecto.Migration.up(version: 3)` and `down` calls `down(version: 3)`. File storage is per node.
- Assets content-hashed by a bundler such as Volt: render the replay frame in the app's root layout, `phoenix_replay "/replay", frame_layout: {MyAppWeb.Layouts, :root}`.
- Video export is opt-in: `export: [endpoint: MyAppWeb.Endpoint]`, with `{:playwright_ex, "~> 0.14"}`, Playwright's Chromium and `ffmpeg`.

`PhoenixReplay.Config` documents every option.

## 4. Keep it private

- Mount the dashboard behind the app's own authentication: a scope piped through an admin check, `on_mount:` hooks, and `authorize: MyApp.ReplayAuthorization` for per-recording rules. Never on a public route.
- `PhoenixReplay.Sanitizer.Default` filters keys such as `password`, `token`, `secret`, `card_number`, `cvv` and `otp` in assigns and params. Write a custom sanitizer for other sensitive assigns rather than renaming them.
- Wrap form controls that may hold sensitive free text in `data-phx-replay-ignore`; the browser never reads them. Passwords, card and one-time-code fields are never read anyway.
- `redact:` masks values matching regexes in everything stored.

## 5. Check it works

1. `mix compile --warnings-as-errors` and `mix test`; tests should record nothing.
2. Start the server, use a recorded page, then close the tab: a session is saved when it ends.
3. Open the dashboard (`/dev/replay` in development) and replay it, or read it from code with the `phoenix-replay-debugging` skill.

## Pitfalls

- A view that renders differently because of browser-only code, such as a list a script filters, replays without that code. Report the state with `replayState(key, changes)` and render it with `replay_render/1`, declared by `PhoenixReplay.Replayable`.
- Streams and uploads are not replayed: their contents are not kept in assigns.
- Do not name an assign `:phoenix_replay_state`; the replay uses it.
- Recording state is buffered in memory until a session ends. Set `max_memory:` when recording many long sessions with `keep:` sampling.
