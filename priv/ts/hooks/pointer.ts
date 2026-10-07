import { ViewHook } from 'phoenix_live_view'

import { DOWN, type Move, type Press, TOUCH, type Track } from '../client/pointer_track'
import { lastAtOrBefore } from '../timeline'
import { TIME_EVENT } from './scrubber'

/** Samples further apart are not interpolated between: the pointer rested. */
const MAX_GAP_MS = 1_000
const SVG = 'http://www.w3.org/2000/svg'
const ARROW = 'M0 0V16.5L4.6 12.2L7.6 18.8L10.3 17.6L7.4 11.1H13.2Z'

/**
 * Draws a recording's pointer track over the replay: the cursor, moved
 * between samples, with a short trail; a ripple for each press, on the
 * pressed element when the replayed page has it; a fingertip for each
 * touch that is down, with the same trail since it went down. It also
 * scrolls the replayed page as recorded.
 *
 * The element carries the track as JSON in `data-track`, the recorded
 * viewport in `data-width` and `data-height`, and how long the path behind
 * the cursor and a press's ripple are drawn, in milliseconds, in
 * `data-trail` and `data-ripple`, from `PhoenixReplay.Recording.PointerTrack`,
 * whose values the video export plans with too. It sits beside the frame
 * as a `[data-frame-overlay]`, which FrameViewport sizes like the frame.
 * It follows the time the Scrubber announces, and reads its size on every
 * draw, so whoever holds it may resize it. It scrolls the page only while
 * the element has `data-follow-scroll`, and then on every draw, so a page
 * that re-rendered or was scrolled by hand goes back where the user was. While the element has
 * `data-rotated`, the frame shows the other orientation than recorded, so
 * nothing is drawn and the page is not scrolled.
 */
export class Pointer extends ViewHook {
  private track: Track = { moves: [], presses: [], scrolls: [] }
  private moves = new Map<number, Move[]>()
  private svg?: SVGSVGElement
  private at?: number
  private trailMs = 0
  private rippleMs = 0
  private readonly onTime = (event: Event): void =>
    this.render((event as CustomEvent<number>).detail)

  mounted(): void {
    this.track = { ...this.track, ...(JSON.parse(this.el.dataset.track ?? '{}') as Partial<Track>) }
    this.trailMs = Number(this.el.dataset.trail)
    this.rippleMs = Number(this.el.dataset.ripple)

    for (const move of this.track.moves) {
      const slot = this.moves.get(move[3]) ?? []
      slot.push(move)
      this.moves.set(move[3], slot)
    }

    this.svg = document.createElementNS(SVG, 'svg')
    this.svg.setAttribute('width', '100%')
    this.svg.setAttribute('height', '100%')
    this.svg.style.overflow = 'visible'
    this.el.append(this.svg)
    this.size()
    window.addEventListener(TIME_EVENT, this.onTime)
  }

  updated(): void {
    this.size()
    if (this.at !== undefined) this.render(this.at)
  }

  destroyed(): void {
    window.removeEventListener(TIME_EVENT, this.onTime)
  }

  /** Draws the pointer as it was `ms` into the recording. */
  render(ms: number): void {
    const svg = this.svg
    if (!svg) return

    this.at = ms
    this.size()
    svg.replaceChildren()

    if (this.el.dataset.rotated !== undefined) return

    this.scroll(ms)

    const mouse = this.moves.get(0) ?? []
    this.appendTrail(mouse, ms - this.trailMs, ms)

    for (const press of this.track.presses) {
      const [at, kind] = press
      if (kind === DOWN && at <= ms && ms - at < this.rippleMs)
        svg.append(this.ripple(press, (ms - at) / this.rippleMs))
    }

    for (const [
      slot,
      {
        since,
        at: [x, y]
      }
    ] of this.touchesDown(ms)) {
      this.appendTrail(this.moves.get(slot) ?? [], Math.max(ms - this.trailMs, since), ms)
      svg.append(this.fingertip(slot, x, y))
    }

    const cursor = position(mouse, ms)
    if (cursor && !this.touching(ms)) svg.append(this.cursor(cursor[0], cursor[1]))
  }

  private size(): void {
    const width = Number(this.el.dataset.width)
    const height = Number(this.el.dataset.height)
    if (this.svg && width && height) this.svg.setAttribute('viewBox', `0 0 ${width} ${height}`)
  }

  private frame(): HTMLIFrameElement | null {
    return this.el.parentElement?.querySelector('iframe') ?? null
  }

  private scroll(ms: number): void {
    if (this.el.dataset.followScroll === undefined) return
    const latest = this.track.scrolls[lastAtOrBefore(this.track.scrolls, ms, sampleAt)]
    const page = this.frame()?.contentWindow
    if (!latest || !page) return

    const [, x, y] = latest
    if (page.scrollX !== x || page.scrollY !== y) page.scrollTo(x, y)
  }

  // The path a pointer moved along after `from`, up to `ms`. A slot's
  // moves span all its touches, so a fingertip's starts at its press.
  private appendTrail(moves: Move[], from: number, ms: number): void {
    const trail = moves.filter(([at]) => at > from && at <= ms)
    if (trail.length > 1) this.svg?.append(this.trail(trail))
  }

  // A touch is down from its press until its release: where it is, and
  // since when.
  private touchesDown(ms: number): Map<number, { since: number; at: [number, number] }> {
    const down = new Map<number, { since: number; at: [number, number] }>()

    for (const [at, kind, x, y, slot, type] of this.track.presses) {
      if (at > ms || type !== TOUCH) continue
      if (kind === DOWN) down.set(slot, { since: at, at: [x, y] })
      else down.delete(slot)
    }

    for (const [slot, touch] of down) {
      const moved = position(this.moves.get(slot) ?? [], ms)
      if (moved) touch.at = moved
    }

    return down
  }

  // The cursor hides while the last press was a touch.
  private touching(ms: number): boolean {
    const last = this.track.presses[lastAtOrBefore(this.track.presses, ms, sampleAt)]
    if (!last) return false

    const [, , , , , type] = last
    return type === TOUCH
  }

  // On the pressed element when the replay has it, as a re-render can lay
  // the page out slightly differently; on the recorded point otherwise.
  private anchor(press: Press): [number, number] {
    const [, , x, y, , , target, fx, fy] = press
    const element = target ? this.frame()?.contentDocument?.getElementById(target) : null
    if (!element) return [x, y]

    const rect = element.getBoundingClientRect()
    return [rect.left + (rect.width * fx) / 1000, rect.top + (rect.height * fy) / 1000]
  }

  private trail(moves: Move[]): SVGElement {
    const line = element('polyline', {
      points: moves.map(([, x, y]) => `${x},${y}`).join(' '),
      fill: 'none',
      'stroke-width': '3',
      'stroke-linecap': 'round',
      'stroke-linejoin': 'round'
    })
    line.style.stroke = 'var(--color-accent)'
    line.style.opacity = '0.35'
    return line
  }

  private ripple(press: Press, progress: number): SVGElement {
    const [x, y] = this.anchor(press)
    const circle = element('circle', { cx: String(x), cy: String(y), r: String(6 + 18 * progress) })
    circle.style.fill = 'var(--color-accent)'
    circle.style.opacity = String(0.45 * (1 - progress))
    return circle
  }

  private fingertip(slot: number, x: number, y: number): SVGElement {
    const circle = element('circle', {
      cx: String(x),
      cy: String(y),
      r: '14',
      'data-slot': String(slot)
    })
    circle.style.fill = 'var(--color-accent)'
    circle.style.opacity = '0.3'
    circle.style.stroke = 'var(--color-accent)'
    return circle
  }

  private cursor(x: number, y: number): SVGElement {
    const arrow = element('path', {
      d: ARROW,
      transform: `translate(${x} ${y})`,
      fill: '#18181b',
      stroke: '#ffffff',
      'stroke-width': '1.2',
      'data-cursor': ''
    })
    return arrow
  }
}

const element = (name: string, attributes: Record<string, string>): SVGElement => {
  const node = document.createElementNS(SVG, name)
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value)
  return node
}

const sampleAt = ([at]: readonly [number, ...unknown[]]): number => at

/** Where the pointer was at `ms`, between the samples around it, or `null` before the first. */
export const position = (moves: Move[], ms: number): [number, number] | null => {
  const index = lastAtOrBefore(moves, ms, sampleAt)
  const current = moves[index]
  if (!current) return null

  const [at, x, y] = current
  const next = moves[index + 1]
  if (!next || next[0] - at > MAX_GAP_MS || next[0] === at) return [x, y]

  const progress = (ms - at) / (next[0] - at)
  return [x + (next[1] - x) * progress, y + (next[2] - y) * progress]
}
