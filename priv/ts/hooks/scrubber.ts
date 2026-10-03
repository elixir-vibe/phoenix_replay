import { ViewHook } from 'phoenix_live_view'
import { clamp, indexAt } from '../timeline'

/**
 * Maps pointer and keyboard input on the timeline to player events, and
 * animates the thumb between events while the server plays.
 */
export class Scrubber extends ViewHook {
  private offsets: number[] = []
  private frame: number | undefined
  private dragging = false
  private sentIndex: number | undefined

  mounted(): void {
    this.offsets = JSON.parse(this.el.dataset.offsets ?? '[]') as number[]
    this.el.addEventListener('pointerdown', this.onPointerDown)
    this.el.addEventListener('pointermove', this.onPointerMove)
    this.el.addEventListener('pointerup', this.onPointerUp)
    this.el.addEventListener('keydown', this.onKeyDown)
    this.animate()
  }

  updated(): void {
    this.animate()
  }

  destroyed(): void {
    this.stop()
  }

  private readonly onPointerDown = (event: PointerEvent): void => {
    event.preventDefault()
    this.dragging = true
    this.sentIndex = undefined
    this.el.setPointerCapture(event.pointerId)
    this.seek(event)
  }

  private readonly onPointerMove = (event: PointerEvent): void => {
    if (this.dragging) this.seek(event)
  }

  private readonly onPointerUp = (event: PointerEvent): void => {
    this.dragging = false
    this.el.releasePointerCapture(event.pointerId)
  }

  private readonly onKeyDown = (event: KeyboardEvent): void => {
    const action = { ArrowLeft: 'previous', ArrowRight: 'next', ' ': 'toggle' }[event.key]
    if (action === undefined) return
    event.preventDefault()
    this.push(action)
  }

  private seek(event: PointerEvent): void {
    const rect = this.el.getBoundingClientRect()
    const ms = clamp((event.clientX - rect.left) / rect.width, 0, 1) * this.number('duration')
    const index = indexAt(this.offsets, ms)
    this.stop()
    this.place(ms)

    if (index !== this.sentIndex) {
      this.sentIndex = index
      this.push('seek', { index })
    }
  }

  private animate(): void {
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
  }

  private push(event: string, payload: object = {}): void {
    this.pushEvent(event, payload).catch(() => undefined)
  }

  private number(key: string): number {
    return Number(this.el.dataset[key] ?? 0)
  }
}
