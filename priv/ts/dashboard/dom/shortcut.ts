import { tinykeys } from 'tinykeys'

/**
 * Focuses the page's `[data-shortcut="/"]` field when `/` is pressed,
 * with Shift or without, as the keyboard layout needs, unless a text field
 * already has focus or another modifier is held, as
 * [tinykeys](https://github.com/jamiebuilds/tinykeys) leaves those alone.
 */
export const searchShortcut = (target: Window): (() => void) =>
  tinykeys(target, {
    '[Shift]+/': (event) => {
      const field = target.document.querySelector<HTMLElement>('[data-shortcut="/"]')
      if (!field) return

      event.preventDefault()
      field.focus()
    }
  })
