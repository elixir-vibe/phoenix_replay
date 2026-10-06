import type { ViewHook } from 'phoenix_live_view'

export type Pushed = [event: string, payload: unknown]

/**
 * Mounts `Hook` on `el`, recording the events it pushes instead of sending
 * them; `receive` plays an event the server pushes to it.
 */
export const mountHook = <T extends ViewHook>(
  Hook: new (view: null, el: HTMLElement) => T,
  el: HTMLElement
): { hook: T; pushed: Pushed[]; receive: (event: string, payload?: unknown) => void } => {
  document.body.append(el)
  const hook = new Hook(null, el)
  const pushed: Pushed[] = []
  const handlers = new Map<string, (payload: unknown) => void>()

  hook.pushEvent = ((event: string, payload: unknown) => {
    pushed.push([event, payload])
    return Promise.resolve()
  }) as T['pushEvent']

  hook.handleEvent = ((event: string, callback: (payload: unknown) => void) => {
    handlers.set(event, callback)
    return callback
  }) as unknown as T['handleEvent']

  hook.mounted?.()
  return { hook, pushed, receive: (event, payload = {}) => handlers.get(event)?.(payload) }
}

/** Builds an element from an HTML string. */
export const html = (source: string): HTMLElement => {
  const template = document.createElement('template')
  template.innerHTML = source.trim()
  return template.content.firstElementChild as HTMLElement
}
