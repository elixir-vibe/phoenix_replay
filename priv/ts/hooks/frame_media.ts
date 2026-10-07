import { ViewHook } from 'phoenix_live_view'

import { applyMedia, type Media } from '../dom/media'

/**
 * Gives the replayed page the media features the user's browser had, from
 * the frame's `data-media`, a JSON object such as `{"pointer": "coarse"}`,
 * each time the page loads and when they change; see `applyMedia`.
 */
export class FrameMedia extends ViewHook<HTMLIFrameElement> {
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
    applyMedia(this.el.contentDocument, JSON.parse(this.el.dataset.media ?? '{}') as Media)
  }
}
