/**
 * Focuses the page's `[data-shortcut="/"]` field when `/` is pressed,
 * unless a text field already has focus or a modifier is held.
 */
export const searchShortcut = (target: Window): (() => void) => {
  const listener = (event: KeyboardEvent): void => {
    if (event.key !== '/' || event.metaKey || event.ctrlKey || event.altKey) return

    const active = target.document.activeElement
    if (active instanceof HTMLElement && (active.isContentEditable || typing(active))) return

    const field = target.document.querySelector<HTMLElement>('[data-shortcut="/"]')
    if (!field) return

    event.preventDefault()
    field.focus()
  }

  target.addEventListener('keydown', listener)
  return () => target.removeEventListener('keydown', listener)
}

const typing = (element: HTMLElement): boolean =>
  ['INPUT', 'TEXTAREA', 'SELECT'].includes(element.tagName)
