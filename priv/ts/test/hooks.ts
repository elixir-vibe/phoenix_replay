import type { ViewHook } from 'phoenix_live_view'

export type Pushed = [event: string, payload: unknown]

/** Mounts `Hook` on `el` and records the events it pushes instead of sending them. */
export const mountHook = <T extends ViewHook>(
  Hook: new (view: null, el: HTMLElement) => T,
  el: HTMLElement
): { hook: T; pushed: Pushed[] } => {
  document.body.append(el)
  const hook = new Hook(null, el)
  const pushed: Pushed[] = []

  hook.pushEvent = ((event: string, payload: unknown) => {
    pushed.push([event, payload])
    return Promise.resolve()
  }) as T['pushEvent']

  hook.mounted?.()
  return { hook, pushed }
}

/** Builds an element from an HTML string. */
export const html = (source: string): HTMLElement => {
  const template = document.createElement('template')
  template.innerHTML = source.trim()
  return template.content.firstElementChild as HTMLElement
}
