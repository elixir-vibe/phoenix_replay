import type { Push } from './pointer'

/** The browser's viewport, as PhoenixReplay records it. */
export interface ReplayViewport {
  width: number
  height: number
  dpr: number
}

/** The window's viewport now. */
export const viewport = (target: Window = window): ReplayViewport => ({
  width: target.innerWidth,
  height: target.innerHeight,
  dpr: target.devicePixelRatio
})

const EVENT = 'phx_replay:viewport'
/** Milliseconds the viewport must stay unchanged before it is sent, as a rotation settles. */
const QUIET_MS = 200

/**
 * Sends the viewport as it changes, a resized window or a rotated phone,
 * once it has stayed the same for a moment, rather than with the user's
 * next click. `replayRecorder` runs it while the page is recorded.
 */
export class ViewportRecorder {
  private sent: string
  private timer: ReturnType<typeof setTimeout> | undefined
  private readonly onResize = (): void => {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.send(), QUIET_MS)
  }

  constructor(
    private readonly push: Push,
    private readonly target: Window
  ) {
    // The LiveView connected with the viewport of this moment.
    this.sent = JSON.stringify(viewport(target))
    target.addEventListener('resize', this.onResize, { passive: true })
  }

  stop(): void {
    clearTimeout(this.timer)
    this.target.removeEventListener('resize', this.onResize)
  }

  private send(): void {
    const now = viewport(this.target)
    const encoded = JSON.stringify(now)
    if (encoded === this.sent) return

    this.sent = encoded
    this.push(EVENT, now)
  }
}
