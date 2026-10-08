/** Where the theme chosen with the toggle is kept. */
export const THEME_KEY = 'phoenix_replay:theme'

const isDark = (target: Window): boolean => {
  const chosen = target.document.documentElement.dataset.theme
  return chosen ? chosen === 'dark' : target.matchMedia('(prefers-color-scheme: dark)').matches
}

/**
 * Switches between the light and dark themes when a `[data-theme-toggle]`
 * button is clicked, by setting `data-theme` on `<html>`, and keeps the
 * choice for the next visit. The layout applies a kept choice before the
 * page paints. Returns a function that stops.
 */
export const themeToggle = (target: Window): (() => void) => {
  const onClick = (event: Event): void => {
    if (!(event.target instanceof Element) || !event.target.closest('[data-theme-toggle]')) return

    const theme = isDark(target) ? 'light' : 'dark'
    target.document.documentElement.dataset.theme = theme

    try {
      target.localStorage.setItem(THEME_KEY, theme)
    } catch {
      // Storage can be unavailable, as in private windows; the switch still applies.
    }
  }

  target.document.addEventListener('click', onClick)
  return () => target.document.removeEventListener('click', onClick)
}
