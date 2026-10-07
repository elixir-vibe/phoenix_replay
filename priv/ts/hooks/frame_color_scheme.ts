import { ViewHook } from 'phoenix_live_view'

import { applyColorScheme } from '../dom/color_scheme'

/**
 * Gives the replayed page the color scheme the user had, from the frame's
 * `data-color-scheme`, each time the page loads and when the recorded
 * scheme changes; see `applyColorScheme`.
 */
export class FrameColorScheme extends ViewHook<HTMLIFrameElement> {
  private readonly onLoad = (): void => this.apply()

  mounted(): void {
    this.el.addEventListener('load', this.onLoad)
    this.apply()
  }

  updated(): void {
    this.apply()
  }

  destroyed(): void {
    this.el.removeEventListener('load', this.onLoad)
  }

  private apply(): void {
    applyColorScheme(this.el.contentDocument, this.el.dataset.colorScheme)
  }
}
