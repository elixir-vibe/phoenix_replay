# How It Works

## Recording

`PhoenixReplay.Recorder` is an `on_mount` hook. On the connected mount it registers the session and attaches lifecycle hooks to the LiveView:

- `handle_params` records the URL and params,
- `handle_info` records message tags (never message contents),
- `after_render` records the assigns that changed in the render,
- `handle_event` takes the batches the browser recorder sends, the pointer, client state and viewport, before your view sees them.

Events your view handles are recorded by `PhoenixReplay.Capture.ViewEvents` from LiveView's `[:phoenix, :live_view, :handle_event, :start]` telemetry, which wraps the `on_mount` hooks too, so an event one of your hooks handles and halts is recorded as well.

LiveComponents have no `on_mount` hook, so `PhoenixReplay.Capture.LiveComponents` records them from LiveView's component telemetry, which runs in the LiveView process with the component's socket. It records events handled by components, the assigns each update or event changed, and component removals.

Each event carries a millisecond offset from the start of the session. Recorder state lives in `socket.private`, so your assigns are untouched.

## Buffering

Events are written by the LiveView process straight into an ETS table, `PhoenixReplay.Session.Buffer`, with no message passing on the hot path. The view and its components share one counter per session, so events stay in order.

The table is owned by the application rather than a worker process, so in-progress recordings survive any worker restart.

## Saving

`PhoenixReplay.Session.Monitor` monitors each recorded process. When it exits, the session is either discarded, when the user never interacted, or saved by `PhoenixReplay.Session.Finalizer` in a supervised task, with retries. The session leaves the buffer once the task finishes, and `PhoenixReplay.Telemetry` reports the outcome. When the monitor restarts, it re-attaches to every buffered session.

`PhoenixReplay.Storage.Retention` deletes stored recordings beyond the configured age or count.

## Replaying

The player page, `PhoenixReplay.Web.Live.Show`, owns playback: it schedules each step after the recorded gap, divided by the playback speed. It drives a frame, an iframe running `PhoenixReplay.Web.Live.Frame`, over a private PubSub channel per viewer.

The frame assigns the recorded assigns at the current position and renders your view's template. Recordings made with older code are first brought up to date by your `PhoenixReplay.Migration` modules, and an assign a template reads that the recording lacks is set to `nil`. When the frame renders in your root layout, it renders the layout again with the same assigns and gives the page's `<html>` and `<body>` the attributes it renders. Before LiveView diffs the result, `PhoenixReplay.Web.Rendering` rewrites the rendered tree so every LiveComponent renders through `PhoenixReplay.Web.Live.ReplayComponent` with its recorded assigns. Templates that fail with the recorded assigns show a placeholder instead of crashing the frame, and events from the replayed template are ignored.
