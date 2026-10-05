import { ViewHook } from 'phoenix_live_view'
import { TIME_EVENT } from './scrubber'

/** `[at, x, y, slot]`: a pointer position, slot `0` the mouse or pen. */
type Move = [number, number, number, number]
/** `[at, kind, x, y, slot, type, target, fx, fy]`: `kind` 0 down, 1 up; `type` 0 mouse, 1 touch, 2 pen. */
type Press = [number, number, number, number, number, number, string | null, number, number]
/** `[at, x, y]`: the page's scroll offset. */
type Scroll = [number, number, number]

interface Track {
  moves: Move[]
  presses: Press[]
  scrolls: Scroll[]
}

/** How long a press ripple lasts, in milliseconds. */
const RIPPLE_MS = 600
/** How much of the path behind the cursor is drawn, in milliseconds. */
const TRAIL_MS = 500
/** Samples further apart are not interpolated between: the pointer rested. */
const MAX_GAP_MS = 1_000
const TOUCH = 1
const SVG = 'http://www.w3.org/2000/svg'
const ARROW = 'M0 0V16.5L4.6 12.2L7.6 18.8L10.3 17.6L7.4 11.1H13.2Z'

/**
 * Draws a recording's pointer track over the replay: the cursor, moved
 * between samples, with a short trail; a ripple for each press, on the
 * pressed element when the replayed page has it; a fingertip for each
 * touch that is down. It also scrolls the replayed page as recorded.
 *
 * The element carries the track as JSON in `data-track` and the recorded
 * viewport in `data-width` and `data-height`, and sits beside the frame
 * as a `[data-frame-overlay]`, which FrameViewport sizes like the frame.
 * It follows the time the Scrubber announces.
 */
export class Pointer extends ViewHook {
  private track: Track = { moves: [], presses: [], scrolls: [] }
  private moves = new Map<number, Move[]>()
  private svg?: SVGSVGElement
  private scrolled = ''
  private readonly onTime = (event: Event): void =>
    this.render((event as CustomEvent<number>).detail)

  mounted(): void {
    this.track = { ...this.track, ...(JSON.parse(this.el.dataset.track ?? '{}') as Partial<Track>) }

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
  }

  destroyed(): void {
    window.removeEventListener(TIME_EVENT, this.onTime)
  }

  /** Draws the pointer as it was `ms` into the recording. */
  render(ms: number): void {
    const svg = this.svg
    if (!svg) return

    this.scroll(ms)
    svg.replaceChildren()

    const mouse = this.moves.get(0) ?? []
    const trail = mouse.filter(([at]) => at > ms - TRAIL_MS && at <= ms)
    if (trail.length > 1) svg.append(this.trail(trail))

    for (const press of this.track.presses) {
      const [at, kind] = press
      if (kind === 0 && at <= ms && ms - at < RIPPLE_MS)
        svg.append(this.ripple(press, (ms - at) / RIPPLE_MS))
    }

    for (const [slot, [x, y]] of this.touchesDown(ms)) svg.append(this.fingertip(slot, x, y))

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
    const latest = this.track.scrolls[lastAtOrBefore(this.track.scrolls, ms)]
    if (!latest) return

    const [, x, y] = latest
    const key = `${x},${y}`
    if (key === this.scrolled) return

    this.scrolled = key
    this.frame()?.contentWindow?.scrollTo(x, y)
  }

  // A touch is down from its press until its release.
  private touchesDown(ms: number): Map<number, [number, number]> {
    const down = new Map<number, [number, number]>()

    for (const [at, kind, x, y, slot, type] of this.track.presses) {
      if (at > ms || type !== TOUCH) continue
      if (kind === 0) down.set(slot, [x, y])
      else down.delete(slot)
    }

    for (const slot of down.keys()) {
      const moved = position(this.moves.get(slot) ?? [], ms)
      if (moved) down.set(slot, moved)
    }

    return down
  }

  // The cursor hides while the last press was a touch.
  private touching(ms: number): boolean {
    return this.track.presses[lastAtOrBefore(this.track.presses, ms)]?.[5] === TOUCH
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

/** The index of the last sample at or before `ms`, or `-1`. Samples are ordered by time. */
export const lastAtOrBefore = (
  samples: ReadonlyArray<readonly number[] | Press>,
  ms: number
): number => {
  let low = 0
  let high = samples.length - 1
  let found = -1

  while (low <= high) {
    const middle = (low + high) >> 1
    const at = samples[middle]?.[0]
    if (typeof at === 'number' && at <= ms) {
      found = middle
      low = middle + 1
    } else {
      high = middle - 1
    }
  }

  return found
}

/** Where the pointer was at `ms`, between the samples around it, or `null` before the first. */
export const position = (moves: Move[], ms: number): [number, number] | null => {
  const index = lastAtOrBefore(moves, ms)
  const current = moves[index]
  if (!current) return null

  const [at, x, y] = current
  const next = moves[index + 1]
  if (!next || next[0] - at > MAX_GAP_MS || next[0] === at) return [x, y]

  const progress = (ms - at) / (next[0] - at)
  return [x + (next[1] - x) * progress, y + (next[2] - y) * progress]
}
