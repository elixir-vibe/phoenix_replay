/**
 * Records the pointer, touches and scrolling, in batches sent as
 * `phx_replay:pointer`, while a recorded LiveView with `:pointer`
 * configured asks for it. `replayRecorder` starts and stops it.
 */

import {
  type Batch,
  DOWN,
  MOUSE,
  PEN,
  type PointerKind,
  type Press,
  type PressKind,
  TOUCH,
  UP
} from './pointer_track'

/** The settings the server sends; see the `:pointer` option. */
export interface PointerSettings {
  /** Milliseconds between recorded positions of a pointer. */
  sample: number
  /** Milliseconds between recorded scroll offsets. */
  scroll: number
  /** Milliseconds between batches sent. */
  flush: number
  /** Positions, presses and scrolls a batch holds before it is sent early. */
  max_points: number
}

/** Sends a batch to the recorded LiveView as `event`. */
export type Push = (event: string, value: unknown) => void

const EVENT = 'phx_replay:pointer'

/** Records the pointer until stopped; see `replayRecorder`. */
export class PointerRecorder {
  private moves: number[] = []
  private presses: Press[] = []
  private scrolls: number[] = []
  private started = 0
  private readonly sampled = new Map<string, number>()
  private readonly trailing = new Map<string, ReturnType<typeof setTimeout>>()
  private readonly slots = new Map<number, number>()
  private readonly timer: ReturnType<typeof setInterval>
  private readonly listeners: [EventTarget, string, EventListener][]

  constructor(
    private readonly push: Push,
    private readonly target: Window,
    private readonly settings: PointerSettings
  ) {
    const document = target.document

    this.listeners = [
      [document, 'pointermove', (event) => this.move(event as PointerEvent)],
      [document, 'pointerdown', (event) => this.press(event as PointerEvent, DOWN)],
      [document, 'pointerup', (event) => this.press(event as PointerEvent, UP)],
      [document, 'pointercancel', (event) => this.press(event as PointerEvent, UP)],
      [target, 'scroll', () => this.throttle('scroll', settings.scroll, () => this.scroll())],
      [document, 'visibilitychange', () => document.hidden && this.flush()]
    ]

    for (const [on, name, listener] of this.listeners) {
      on.addEventListener(name, listener, { passive: true, capture: true })
    }

    this.timer = setInterval(() => this.flush(), settings.flush)
    this.scroll()
  }

  stop(): void {
    this.flush()
    clearInterval(this.timer)
    for (const timeout of this.trailing.values()) clearTimeout(timeout)

    for (const [on, name, listener] of this.listeners) {
      on.removeEventListener(name, listener, { capture: true })
    }
  }

  private move(event: PointerEvent): void {
    const slot = this.slot(event)
    const { clientX, clientY } = event

    this.throttle(`move:${slot}`, this.settings.sample, () =>
      this.add(() => this.moves.push(this.dt(), Math.round(clientX), Math.round(clientY), slot))
    )
  }

  private press(event: PointerEvent, kind: PressKind): void {
    const slot = this.slot(event)
    const x = Math.round(event.clientX)
    const y = Math.round(event.clientY)
    const [target, fx, fy] = kind === DOWN ? anchor(event) : [null, 0, 0]

    this.add(() => this.presses.push([this.dt(), kind, x, y, slot, type(event), target, fx, fy]))
    if (kind === UP && event.pointerType === 'touch') this.slots.delete(event.pointerId)
  }

  private scroll(): void {
    const { scrollX, scrollY } = this.target
    this.add(() => this.scrolls.push(this.dt(), Math.round(scrollX), Math.round(scrollY)))
  }

  // The mouse and pen share slot 0; each finger gets the lowest free one.
  private slot(event: PointerEvent): number {
    if (event.pointerType !== 'touch') return 0

    const known = this.slots.get(event.pointerId)
    if (known !== undefined) return known

    const taken = new Set(this.slots.values())
    let slot = 1
    while (taken.has(slot)) slot++
    this.slots.set(event.pointerId, slot)
    return slot
  }

  // At most one sample per `interval`, plus a last one when things settle,
  // so a resting position is exact.
  private throttle(key: string, interval: number, sample: () => void): void {
    const now = performance.now()
    const last = this.sampled.get(key) ?? -Infinity
    clearTimeout(this.trailing.get(key))

    if (now - last >= interval) {
      this.sampled.set(key, now)
      sample()
    } else {
      this.trailing.set(
        key,
        setTimeout(
          () => {
            this.sampled.set(key, performance.now())
            sample()
          },
          interval - (now - last)
        )
      )
    }
  }

  private add(sample: () => void): void {
    if (this.count() === 0) this.started = performance.now()
    sample()
    if (this.count() >= this.settings.max_points) this.flush()
  }

  private count(): number {
    return this.moves.length / 4 + this.presses.length + this.scrolls.length / 3
  }

  private dt(): number {
    return Math.round(performance.now() - this.started)
  }

  private flush(): void {
    if (this.count() === 0) return

    const value: Batch = {
      span: Math.round(performance.now() - this.started),
      m: this.moves,
      p: this.presses,
      s: this.scrolls
    }

    this.moves = []
    this.presses = []
    this.scrolls = []
    this.push(EVENT, value)
  }
}

const type = (event: PointerEvent): PointerKind =>
  event.pointerType === 'touch' ? TOUCH : event.pointerType === 'pen' ? PEN : MOUSE

/** The nearest pressed element with a lasting id, and the point within it in thousandths. */
const anchor = (event: PointerEvent): [string | null, number, number] => {
  // LiveView's own ids, phx-…, change with every mount, so the replay never has them.
  const element =
    event.target instanceof Element ? event.target.closest('[id]:not([id^="phx-"])') : null
  if (!element) return [null, 0, 0]

  const rect = element.getBoundingClientRect()
  const share = (offset: number, size: number): number =>
    size > 0 ? Math.min(1000, Math.max(0, Math.round((offset / size) * 1000))) : 0

  return [
    element.id,
    share(event.clientX - rect.left, rect.width),
    share(event.clientY - rect.top, rect.height)
  ]
}
