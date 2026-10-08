# PhoenixReplay's TypeScript

Grouped by where the code runs, then by feature:

- `client/` — runs in your users' pages: the published `phoenix_replay` module, the recorder, built to `priv/static/phoenix_replay.js`, with its declarations in `phoenix_replay.d.ts` beside it.
- `replay/` — runs in the replay frame, under the dashboard's layout or your app's: puts the page back as it was recorded.
- `dashboard/` — the dashboard, built to `priv/static/dashboard.js`: the player's frame and playback, the recording list, video export, and DOM helpers.
- `shared/` — used by the recorder and the dashboard alike.
- `test/` — helpers for the tests beside each file.

## Names

Names in this code are camelCase. snake_case marks data on the wire: payloads to and from Elixir, typed in `shared/payloads.ts`, keep the server's keys, unconverted, since some are keyed by data that must arrive as written. Files are snake_case, as LiveView's own sources and the Elixir modules they pair with are.
