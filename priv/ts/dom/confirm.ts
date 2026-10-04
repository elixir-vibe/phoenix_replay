/**
 * Asks for confirmation before clicks on elements with `data-confirm`.
 *
 * Phoenix apps usually get this from `phoenix_html`'s JavaScript, but the
 * dashboard loads only the host's Phoenix and LiveView clients. The listener
 * runs in the capture phase, before LiveView handles `phx-click`, and stops a
 * declined click from reaching it.
 */
export const confirmClicks = (
  target: Window,
  ask: (message: string) => boolean = (message) => target.confirm(message)
): (() => void) => {
  const listener = (event: Event): void => {
    const element = (event.target as Element | null)?.closest<HTMLElement>('[data-confirm]')
    if (element && !ask(element.dataset.confirm ?? '')) {
      event.preventDefault()
      event.stopImmediatePropagation()
    }
  }

  target.addEventListener('click', listener, true)
  return () => target.removeEventListener('click', listener, true)
}
