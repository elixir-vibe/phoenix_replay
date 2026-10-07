import type { Push } from './pointer'

/**
 * The browser's viewport, as PhoenixReplay records it: its size and pixel
 * ratio, the screen's orientation angle, and the media settings the page's
 * CSS can see. A setting the browser does not report is left out.
 */
export interface ReplayViewport {
  width: number
  height: number
  dpr: number
  /** `screen.orientation.angle`: 0, 90, 180 or 270. */
  angle?: number
  color_scheme?: 'light' | 'dark'
  reduced_motion?: boolean
  contrast?: 'more' | 'less' | 'no-preference'
  pointer?: 'coarse' | 'fine' | 'none'
  hover?: 'hover' | 'none'
}

// A recorded value and the media query that matches it.
type Choice = readonly [unknown, string]

const choices = (feature: string, values: string[]): Choice[] =>
  values.map((value) => [value, `(${feature}: ${value})`])

// The media settings recorded, each as the first of its values that matches.
const SETTINGS: Record<string, Choice[]> = {
  color_scheme: choices('prefers-color-scheme', ['dark', 'light']),
  reduced_motion: [
    [true, '(prefers-reduced-motion: reduce)'],
    [false, '(prefers-reduced-motion: no-preference)']
  ],
  contrast: choices('prefers-contrast', ['more', 'less', 'no-preference']),
  pointer: choices('pointer', ['coarse', 'fine', 'none']),
  hover: choices('hover', ['hover', 'none'])
}

const QUERIES = Object.values(SETTINGS).flatMap((values) => values.map(([, query]) => query))

const setting = (target: Window, values: Choice[]): unknown =>
  values.find(([, query]) => target.matchMedia(query).matches)?.[0]

/** The window's viewport now. */
export const viewport = (target: Window = window): ReplayViewport => {
  const now: ReplayViewport = {
    width: target.innerWidth,
    height: target.innerHeight,
    dpr: target.devicePixelRatio
  }

  const angle = target.screen?.orientation?.angle
  if (typeof angle === 'number') now.angle = angle

  if (typeof target.matchMedia === 'function')
    for (const [name, values] of Object.entries(SETTINGS)) {
      const value = setting(target, values)
      if (value !== undefined) Object.assign(now, { [name]: value })
    }

  return now
}

const EVENT = 'phx_replay:viewport'
/** Milliseconds the viewport must stay unchanged before it is sent, as a rotation settles. */
const QUIET_MS = 200

/**
 * Sends the viewport as it changes, a resized window, a rotated phone or
 * a switch to dark mode, once it has stayed the same for a moment, rather
 * than with the user's next click. `replayRecorder` runs it while the page
 * is recorded.
 */
export class ViewportRecorder {
  private sent: string
  private timer: ReturnType<typeof setTimeout> | undefined
  private readonly media: MediaQueryList[]
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
    // A turn between the two landscapes keeps the size; settings change alone.
    target.screen?.orientation?.addEventListener('change', this.onResize)
    this.media =
      typeof target.matchMedia === 'function'
        ? QUERIES.map((query) => target.matchMedia(query))
        : []
    for (const list of this.media) list.addEventListener('change', this.onResize)
  }

  stop(): void {
    clearTimeout(this.timer)
    this.target.removeEventListener('resize', this.onResize)
    this.target.screen?.orientation?.removeEventListener('change', this.onResize)
    for (const list of this.media) list.removeEventListener('change', this.onResize)
  }

  private send(): void {
    const now = viewport(this.target)
    const encoded = JSON.stringify(now)
    if (encoded === this.sent) return

    this.sent = encoded
    this.push(EVENT, now)
  }
}
