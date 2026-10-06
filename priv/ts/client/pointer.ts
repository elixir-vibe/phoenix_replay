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
  private readonly pending = new Map<string, () => void>()
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
      [document, 'pointermove', (event) => this.pointerMove(event as PointerEvent)],
      [document, 'pointerdown', (event) => this.pointerPress(event as PointerEvent, DOWN)],
      [document, 'pointerup', (event) => this.pointerPress(event as PointerEvent, UP)],
      [document, 'pointercancel', (event) => this.pointerPress(event as PointerEvent, UP)],
      // Touches are followed with touch events, which keep coming while the
      // browser scrolls or zooms, where pointer events are cancelled.
      [document, 'touchstart', (event) => this.touch(event as TouchEvent, DOWN)],
      [document, 'touchmove', (event) => this.touch(event as TouchEvent, null)],
      [document, 'touchend', (event) => this.touch(event as TouchEvent, UP)],
      [document, 'touchcancel', (event) => this.touch(event as TouchEvent, UP)],
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

  // The mouse and pen share slot 0.
  private pointerMove(event: PointerEvent): void {
    if (event.pointerType !== 'touch') this.move(0, event.clientX, event.clientY)
  }

  private pointerPress(event: PointerEvent, kind: PressKind): void {
    if (event.pointerType === 'touch') return
    const kindOfPointer = event.pointerType === 'pen' ? PEN : MOUSE
    this.press(0, kind, event.clientX, event.clientY, kindOfPointer, event.target)
  }

  // Every finger that changed, each in a slot of its own while it is down.
  private touch(event: TouchEvent, kind: PressKind | null): void {
    for (const touch of Array.from(event.changedTouches)) {
      const slot = this.slot(touch.identifier)

      if (kind === null) {
        this.move(slot, touch.clientX, touch.clientY)
      } else {
        this.press(slot, kind, touch.clientX, touch.clientY, TOUCH, touch.target)
        if (kind === UP) this.slots.delete(touch.identifier)
      }
    }
  }

  private move(slot: number, x: number, y: number): void {
    this.throttle(`move:${slot}`, this.settings.sample, () =>
      this.add(() => this.moves.push(this.dt(), Math.round(x), Math.round(y), slot))
    )
  }

  private press(
    slot: number,
    kind: PressKind,
    clientX: number,
    clientY: number,
    pointer: PointerKind,
    pressed: EventTarget | null
  ): void {
    const x = Math.round(clientX)
    const y = Math.round(clientY)
    const [target, fx, fy] = kind === DOWN ? anchor(pressed, clientX, clientY) : [null, 0, 0]

    // A finger's last position, so a swipe ends where it was lifted.
    if (kind === UP && slot > 0) this.flushMove(slot)
    this.add(() => this.presses.push([this.dt(), kind, x, y, slot, pointer, target, fx, fy]))
  }

  private scroll(): void {
    const { scrollX, scrollY } = this.target
    this.add(() => this.scrolls.push(this.dt(), Math.round(scrollX), Math.round(scrollY)))
  }

  // Each finger gets the lowest free slot from 1. Its identifier can be any
  // number: Safari uses the address of the touch it tracks.
  private slot(identifier: number): number {
    const known = this.slots.get(identifier)
    if (known !== undefined) return known

    const taken = new Set(this.slots.values())
    let slot = 1
    while (taken.has(slot)) slot++
    this.slots.set(identifier, slot)
    return slot
  }

  // Runs a move waiting for the end of its sampling interval now.
  private flushMove(slot: number): void {
    const key = `move:${slot}`
    const pending = this.pending.get(key)
    if (!pending) return

    clearTimeout(this.trailing.get(key))
    this.trailing.delete(key)
    this.pending.delete(key)
    pending()
  }

  // At most one sample per `interval`, plus a last one when things settle,
  // so a resting position is exact.
  private throttle(key: string, interval: number, sample: () => void): void {
    const now = performance.now()
    const last = this.sampled.get(key) ?? -Infinity
    clearTimeout(this.trailing.get(key))

    if (now - last >= interval) {
      this.pending.delete(key)
      this.sampled.set(key, now)
      sample()
    } else {
      const later = (): void => {
        this.pending.delete(key)
        this.sampled.set(key, performance.now())
        sample()
      }

      this.pending.set(key, later)
      this.trailing.set(key, setTimeout(later, interval - (now - last)))
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

/** The nearest pressed element with a lasting id, and the point within it in thousandths. */
const anchor = (
  pressed: EventTarget | null,
  clientX: number,
  clientY: number
): [string | null, number, number] => {
  // LiveView's own ids, phx-…, change with every mount, so the replay never has them.
  const element = pressed instanceof Element ? pressed.closest('[id]:not([id^="phx-"])') : null
  if (!element) return [null, 0, 0]

  const rect = element.getBoundingClientRect()
  const share = (offset: number, size: number): number =>
    size > 0 ? Math.min(1000, Math.max(0, Math.round((offset / size) * 1000))) : 0

  return [
    element.id,
    share(clientX - rect.left, rect.width),
    share(clientY - rect.top, rect.height)
  ]
}
