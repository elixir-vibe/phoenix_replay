/** The event the replay frame receives the attributes of its page's `<html>` with. */
export const ROOT_EVENT = 'phx:phx_replay:root'

/**
 * Gives the replayed page's `<html>` the attributes the app's
 * `:root_attributes` derives from the replayed assigns, such as the theme
 * a session had, as the server pushes them, and returns a function that
 * stops. An attribute set before and now missing or `null` is removed.
 * See `PhoenixReplay.Web.Live.Frame`.
 *
 * Like `replayInputs`, the dashboard's script and the app's own both call
 * this, so it works in either frame layout.
 */
export const replayRoot = (target: Window): (() => void) => {
  const root = target.document.documentElement
  let set = new Set<string>()

  const apply = (event: Event): void => {
    const { attributes } =
      (event as CustomEvent<{ attributes?: Record<string, string | null> }>).detail ?? {}
    const next = new Set<string>()

    for (const [name, value] of Object.entries(attributes ?? {})) {
      if (value === null) continue
      root.setAttribute(name, value)
      next.add(name)
    }

    for (const name of set) if (!next.has(name)) root.removeAttribute(name)
    set = next
  }

  target.addEventListener(ROOT_EVENT, apply)
  return () => target.removeEventListener(ROOT_EVENT, apply)
}
