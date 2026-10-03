# LiveComponents

LiveComponents are recorded and replayed with no changes to the components.

## Recording

LiveComponents have no `on_mount` hook, so the recorder cannot attach to them the way it attaches to views. Instead, `PhoenixReplay.Recorder.Components` listens to LiveView's documented component telemetry:

- `[:phoenix, :live_component, :handle_event, :start]` records the event, with `target: {module, id}`,
- `[:phoenix, :live_component, :update, :stop]` and `[:phoenix, :live_component, :handle_event, :stop]` record the component assigns that changed,
- `[:phoenix, :live_component, :destroyed]` records the removal.

These handlers run in the LiveView process, find its session, and write to the same buffer as the view, so view and component events stay in order. Components of LiveViews that are not recorded cost one ETS lookup per event.

Events handled by a component count as interaction, so a session where the user only used components is kept.

## Replay

The replay frame renders your view's template, which contains your components. Before LiveView diffs the result, every component in the rendered tree is swapped for `PhoenixReplay.Web.Live.ReplayComponent`, which renders the original component module with:

1. the assigns the parent passes in the template, merged with
2. the assigns recorded for that component at the current position.

Nested components are swapped the same way. When you seek, the frame refreshes each component with `send_update/3`, so components update even when their parent's template did not change. A component that fails to render with the recorded assigns shows a placeholder in its place.

## Limitations

State changed by `handle_async/3` inside a component emits no component telemetry and is captured only when the next update or event changes the component again.
