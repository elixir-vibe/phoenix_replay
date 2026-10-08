/** How long a copied element stays marked, in milliseconds. */
const COPIED_MS = 1500

/**
 * Copies links on clicks on elements with `data-copy`.
 *
 * The attribute holds a URL, relative to the page; the absolute URL is
 * written to the clipboard and the element is marked `data-copied` for a
 * moment, so it can say so.
 */
export const copyLinks = (
  target: Window,
  write: (text: string) => Promise<void> = (text) => target.navigator.clipboard.writeText(text)
): (() => void) => {
  const listener = (event: Event): void => {
    const element = (event.target as Element | null)?.closest<HTMLElement>('[data-copy]')
    if (!element) return

    const url = new URL(element.dataset.copy ?? '', target.location.href).href

    // A rejection, or a throw where the clipboard is unavailable, such as
    // on plain HTTP, leaves the element unmarked.
    Promise.resolve()
      .then(() => write(url))
      .then(() => {
        element.dataset.copied = ''
        target.setTimeout(() => delete element.dataset.copied, COPIED_MS)
      })
      .catch(() => undefined)
  }

  target.addEventListener('click', listener)
  return () => target.removeEventListener('click', listener)
}
