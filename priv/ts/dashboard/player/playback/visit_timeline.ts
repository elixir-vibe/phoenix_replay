import { ViewHook } from 'phoenix_live_view'
import { clamp } from '../../../shared/timeline'

/** How far the arrow keys move on the visit's clock, in milliseconds. */
const STEP = 5_000

/**
 * The visit's timeline: moves its playhead between the server's updates
 * while the visit plays, through the pages and the gaps between them, and
 * seeks on the visit's clock. The playhead follows the pointer while it is
 * held, and the server is told once, where it is let go, as a page may
 * have to load there; the arrow keys move it by a few seconds.
 */
export class VisitTimeline extends ViewHook {
  private frame: number | undefined
  private dragging = false

  mounted(): void {
    this.el.addEventListener('pointerdown', this.onPointerDown)
    this.el.addEventListener('pointermove', this.onPointerMove)
    this.el.addEventListener('pointerup', this.onPointerUp)
    this.el.addEventListener('keydown', this.onKeyDown)
    this.animate()
  }

  updated(): void {
    if (!this.dragging) this.animate()
  }

  destroyed(): void {
    this.stop()
  }

  private readonly onPointerDown = (event: PointerEvent): void => {
    event.preventDefault()
    this.dragging = true
    this.el.setPointerCapture(event.pointerId)
    this.stop()
    this.place(this.timeAt(event))
  }

  private readonly onPointerMove = (event: PointerEvent): void => {
    if (this.dragging) this.place(this.timeAt(event))
  }

  private readonly onPointerUp = (event: PointerEvent): void => {
    if (!this.dragging) return
    this.dragging = false
    this.el.releasePointerCapture(event.pointerId)
    this.seek(this.timeAt(event))
  }

  private readonly onKeyDown = (event: KeyboardEvent): void => {
    const step = { ArrowLeft: -STEP, ArrowRight: STEP }[event.key]
    if (step === undefined) return
    event.preventDefault()
    this.seek(clamp(this.number('at') + step, 0, this.number('duration')))
  }

  private timeAt(event: PointerEvent): number {
    const rect = this.el.getBoundingClientRect()
    return clamp((event.clientX - rect.left) / rect.width, 0, 1) * this.number('duration')
  }

  private seek(ms: number): void {
    this.place(ms)
    this.pushEvent('visit_seek', { at: Math.round(ms) }).catch(() => undefined)
  }

  // From the server's moment towards `until`, the next event or the end of
  // a gap, at the playback speed.
  private animate(): void {
    this.stop()
    const at = this.number('at')
    this.place(at)
    if (this.el.dataset.playing !== 'true') return

    const until = this.number('until')
    const speed = this.number('speed')
    const start = performance.now()

    const step = (now: number): void => {
      const ms = Math.min(at + (now - start) * speed, until)
      this.place(ms)
      if (ms < until) this.frame = requestAnimationFrame(step)
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
    if (thumb) thumb.style.left = `${duration > 0 ? (Math.min(ms, duration) / duration) * 100 : 0}%`
  }

  private number(key: string): number {
    return Number(this.el.dataset[key] ?? 0)
  }
}
