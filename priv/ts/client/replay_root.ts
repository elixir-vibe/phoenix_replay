/** The event the replay frame receives its root layout, rendered for the moment shown, with. */
export const ROOT_EVENT = 'phx:phx_replay:root'

/** The root layout of a replayed moment, and attributes for `<html>` besides it. */
interface Root {
  layout?: string | null
  attributes?: Record<string, string | null>
}

/**
 * Gives the replayed page's `<html>` and `<body>` the attributes its root
 * layout renders at the moment shown, such as a theme the assigns choose,
 * as the server pushes them, and returns a function that stops. The page's
 * own layout rendered only once, when the frame loaded. Attributes this
 * set before and the layout no longer renders are removed. See
 * `PhoenixReplay.Web.Live.Frame`.
 *
 * Like `replayInputs`, the dashboard's script and the app's own both call
 * this, so it works in either frame layout.
 */
export const replayRoot = (target: Window): (() => void) => {
  const doc = target.document
  const set = new Map<Element, Set<string>>()

  const copy = (element: Element, attributes: [string, string][]): void => {
    const before = set.get(element) ?? new Set<string>()
    const now = new Set(attributes.map(([name]) => name))

    for (const [name, value] of attributes)
      if (element.getAttribute(name) !== value) element.setAttribute(name, value)
    for (const name of before) if (!now.has(name)) element.removeAttribute(name)
    set.set(element, now)
  }

  const apply = (event: Event): void => {
    const { layout, attributes } = (event as CustomEvent<Root>).detail ?? {}
    const rendered = layout ? new DOMParser().parseFromString(layout, 'text/html') : null
    const extra = Object.entries(attributes ?? {}).filter(
      (entry): entry is [string, string] => entry[1] !== null
    )

    copy(doc.documentElement, [...own(rendered?.documentElement), ...extra])
    if (doc.body) copy(doc.body, own(rendered?.body))
  }

  target.addEventListener(ROOT_EVENT, apply)
  return () => target.removeEventListener(ROOT_EVENT, apply)
}

const own = (element: Element | null | undefined): [string, string][] =>
  element ? Array.from(element.attributes, ({ name, value }) => [name, value]) : []
