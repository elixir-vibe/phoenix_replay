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

The recording also keeps the view module, URL, sanitized params and session, and the start time. Everything passes through the configured sanitizer first; see [Privacy and Security](privacy-and-security.md).

## Which sessions are kept

Recording starts on every connected mount, but a session is saved only if the user interacted with it: it handled an event, in the view or a component, or navigated within the LiveView. Plain page views are discarded when the process exits.

## Sampling and limits

Record a share of sessions with `:sample_rate`, from `0.0` to `1.0`, and cap the events per session with `:max_events`. Set them globally:

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

Per-session options accept `:sample_rate`, `:max_events` and `:sanitizer`. Once a session reaches `:max_events`, further events are dropped and the recording is kept as it is.

## Telemetry

`PhoenixReplay.Telemetry` emits an event when a session is finalized:

- `[:phoenix_replay, :recording, :persisted]` with `event_count` and `duration_ms` measurements,
- `[:phoenix_replay, :recording, :discarded]` for sessions without interaction,
- `[:phoenix_replay, :recording, :failed]` when saving gave up.

Each event fires after the session has left the buffer, so handlers see the finished state.

## Limitations

Replay reconstructs the assigns of LiveViews and LiveComponents. It does not reconstruct:

- streams and uploads, whose contents are not kept in assigns,
- LiveComponent state changed by `handle_async/3`, which emits no telemetry,
- client-only state: scroll position, unsubmitted input without `phx-change`, JavaScript hook state, and `Phoenix.LiveView.JS` commands applied on the client.
