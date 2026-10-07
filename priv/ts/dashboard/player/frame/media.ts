import { ViewHook } from 'phoenix_live_view'

import { applyMedia, type Media } from '../../../replay/media'

// Hides the replayed page's scrollbar while it scrolls, as a touch screen
// overlays its own: a desktop scrollbar would also narrow the page from
// the width it had.
const OVERLAY_SCROLLBAR = 'html{scrollbar-width:none}html::-webkit-scrollbar{display:none}'
const SCROLLBAR_STYLE = 'phx-replay-scrollbar'

/**
 * Gives the replayed page the media features the user's browser had, from
 * the frame's `data-media`, a JSON object such as `{"pointer": "coarse"}`,
 * each time the page loads and when they change; see `applyMedia`. On a
 * touch screen, the page shows no scrollbar either.
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
    const doc = this.el.contentDocument
    const media = JSON.parse(this.el.dataset.media ?? '{}') as Media
    applyMedia(doc, media)
    if (doc) overlayScrollbar(doc, media.pointer === 'coarse')
  }
}

const overlayScrollbar = (doc: Document, touch: boolean): void => {
  const style = doc.getElementById(SCROLLBAR_STYLE)

  if (touch && !style) {
    const added = doc.createElement('style')
    added.id = SCROLLBAR_STYLE
    added.textContent = OVERLAY_SCROLLBAR
    doc.head?.append(added)
  } else if (!touch) {
    style?.remove()
  }
}
