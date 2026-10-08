import { ViewHook } from 'phoenix_live_view'
import { clamp, indexAt } from '../../../shared/timeline'

/** The window event announcing the playback time, in milliseconds, as `detail`. */
export const TIME_EVENT = 'phoenix-replay:time'

/**
 * Maps pointer and keyboard input on the timeline to player events, and
 * animates the thumb between events while the server plays. Each time it
 * places the thumb it announces the time as a `TIME_EVENT`, so overlays
 * such as the pointer follow playback, seeking and dragging alike.
 */
export class Scrubber extends ViewHook {
  private offsets: number[] = []
  private frame: number | undefined
  private dragging = false
  // Where the pointer holds the thumb while dragging.
  private dragAt = 0
  // One drag seek is in flight at a time; the latest waits for it.
  private sending = false
  private queued: { index: number; at: number } | null = null

  mounted(): void {
    this.offsets = JSON.parse(this.el.dataset.offsets ?? '[]') as number[]
    this.el.addEventListener('pointerdown', this.onPointerDown)
    this.el.addEventListener('pointermove', this.onPointerMove)
    this.el.addEventListener('pointerup', this.onPointerUp)
    this.el.addEventListener('keydown', this.onKeyDown)
    this.animate()
  }

  // A patch renders the thumb at the server's time; while dragging it
  // goes straight back under the pointer, before the browser paints.
  updated(): void {
    if (this.dragging) this.place(this.dragAt)
    else this.animate()
  }

  destroyed(): void {
    this.stop()
  }

  private readonly onPointerDown = (event: PointerEvent): void => {
    event.preventDefault()
    this.dragging = true
    this.el.setPointerCapture(event.pointerId)
    this.seek(event)
  }

  private readonly onPointerMove = (event: PointerEvent): void => {
    if (this.dragging) this.seek(event)
  }

  // Where the pointer is let go is where playback stands, even between events.
  private readonly onPointerUp = (event: PointerEvent): void => {
    if (!this.dragging) return
    this.seek(event, true)
    this.dragging = false
    this.el.releasePointerCapture(event.pointerId)
  }

  private readonly onKeyDown = (event: KeyboardEvent): void => {
    const action = { ArrowLeft: 'previous', ArrowRight: 'next', ' ': 'toggle' }[event.key]
    if (action === undefined) return
    event.preventDefault()
    this.push(action)
  }

  // The frame follows the event under the pointer, and the player the
  // time, so the clock reads the pointer's time even between events. Drag
  // seeks go one at a time, the latest replacing any still waiting; letting
  // go drops a waiting one and sends where the thumb was dropped.
  private seek(event: PointerEvent, release = false): void {
    const rect = this.el.getBoundingClientRect()
    const ms = clamp((event.clientX - rect.left) / rect.width, 0, 1) * this.number('duration')
    const seek = { index: indexAt(this.offsets, ms), at: Math.round(ms) }
    this.stop()
    this.dragAt = ms
    this.place(ms)

    if (release) {
      this.queued = null
      this.push('seek', seek)
    } else if (this.sending) {
      this.queued = seek
    } else {
      this.send(seek)
    }
  }

  private send(seek: { index: number; at: number }): void {
    this.sending = true
    this.pushEvent('seek', seek)
      .catch(() => undefined)
      .finally(() => {
        this.sending = false
        const queued = this.queued
        this.queued = null
        if (queued && this.dragging) this.send(queued)
      })
  }

  private animate(): void {
    // While dragging the thumb follows the pointer, not the server.
    if (this.dragging) return
    this.stop()
    const at = this.number('at')
    this.place(at)
    if (this.el.dataset.playing !== 'true' || this.dragging) return

    const nextAt = this.number('nextAt')
    const speed = this.number('speed')
    const start = performance.now()

    const step = (now: number): void => {
      const ms = Math.min(at + (now - start) * speed, nextAt)
      this.place(ms)
      if (ms < nextAt) this.frame = requestAnimationFrame(step)
    }

    this.frame = requestAnimationFrame(step)
  }

  private stop(): void {
    if (this.frame !== undefined) cancelAnimationFrame(this.frame)
    this.frame = undefined
  }

  private place(ms: number): void {
    const thumb = this.el.querySelector<HTMLElement>('[data-thumb]')
    const duration = this.number('duration')
    if (thumb) thumb.style.left = `${duration > 0 ? (ms / duration) * 100 : 0}%`
    window.dispatchEvent(new CustomEvent(TIME_EVENT, { detail: ms }))
  }

  private push(event: string, payload: object = {}): void {
    this.pushEvent(event, payload).catch(() => undefined)
  }

  private number(key: string): number {
    return Number(this.el.dataset[key] ?? 0)
  }
}
