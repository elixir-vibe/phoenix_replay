# Why PhoenixReplay

Session replay tools for the web, such as rrweb-based recorders, run a script in the browser that serializes the DOM and every mutation, input and scroll, and uploads the stream. That works for any site, but for a LiveView app it records the wrong layer.

## The server already knows

A LiveView's HTML is a function of its assigns. Every state the user saw was rendered on the server from assigns the server produced, in response to events the server handled. PhoenixReplay records those events and assigns, and replays a session by rendering your own templates again.

This gives a few properties that DOM recording cannot:

- **Exact.** A replay shows what the server rendered at each step, from the same template, not a reconstruction of browser mutations.
- **Debuggable.** Next to the rendered page, the player shows the event that caused each step and the assigns behind it. You can see that `validate` ran with a given payload and which assigns changed as a result.
- **Small.** Assigns changed by each render are stored, not markup. A 30-second session of active form input is a few kilobytes.
- **Little client cost.** The server records on its own, writing events from the LiveView process without waiting on other processes. The optional browser recorder adds only what the server cannot see, the pointer and form input, in small batches over the LiveView socket.
- **Private by construction.** Sensitive values are filtered on the server before they are stored, using the same keys your forms and assigns already use.

## What it does not record

PhoenixReplay records what LiveView sees, plus what users type and choose in form controls, whether or not the form has a `phx-change`, and, when `:pointer` is on, the pointer and scrolling. It does not record what your JavaScript does with client state, such as rows a script filtered, unless your view renders it with `replay_render/1`, nor focus or styles changed by `Phoenix.LiveView.JS` commands on the client. Passwords, hidden inputs, card fields and one-time codes are never read. Streams and uploads are not replayed, since their contents are not kept in assigns. See [Client state](recording.md#client-state) and [Recording](recording.md#limitations).

For bugs that live in server state — wrong data shown, a form that validated unexpectedly, a flow that ended up somewhere it should not — the assigns timeline is usually the shortest path to the cause.
