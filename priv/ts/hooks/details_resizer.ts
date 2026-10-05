import { ViewHook } from 'phoenix_live_view'

import { clamp } from '../timeline'

/** Where the details pane's height is kept for the next visit. */
export const DETAILS_HEIGHT_KEY = 'phoenix_replay:details-height'
/** The lowest the pane goes, in pixels. */
const MIN_HEIGHT = 96
/** The share of the window the pane may take. */
const MAX_SHARE = 0.7
/** How far an arrow key moves the divider, in pixels. */
const STEP = 16

/**
 * The divider above the event details pane. Dragging it, or its arrow
 * keys, sets the pane's height as the `--details` property of the element
 * named by `data-container`, which sizes both the list and the pane, and
 * keeps it for the next visit.
 *
 * The property is set through the hook's `js()`, so LiveView's patches
 * leave it in place.
 */
export class DetailsResizer extends ViewHook {
  private drag: { y: number; height: number } | null = null

  mounted(): void {
    const saved = Number(read())
    if (saved) this.resize(saved, false)

    this.el.addEventListener('pointerdown', this.onPointerDown)
    this.el.addEventListener('pointermove', this.onPointerMove)
    this.el.addEventListener('pointerup', this.onPointerUp)
    this.el.addEventListener('keydown', this.onKeyDown)
  }

  private readonly onPointerDown = (event: PointerEvent): void => {
    event.preventDefault()
    this.el.setPointerCapture(event.pointerId)
    this.drag = { y: event.clientY, height: this.height() }
  }

  // The divider sits above the pane: dragging it up makes the pane taller.
  private readonly onPointerMove = (event: PointerEvent): void => {
    if (this.drag) this.resize(this.drag.height + this.drag.y - event.clientY, false)
  }

  private readonly onPointerUp = (event: PointerEvent): void => {
    if (!this.drag) return
    this.drag = null
    this.el.releasePointerCapture(event.pointerId)
    write(String(this.height()))
  }

  private readonly onKeyDown = (event: KeyboardEvent): void => {
    const delta = { ArrowUp: STEP, ArrowDown: -STEP }[event.key]
    if (delta === undefined) return
    event.preventDefault()
    this.resize(this.height() + delta, true)
  }

  private resize(height: number, save: boolean): void {
    const container = this.container()
    if (!container) return

    const clamped = Math.round(clamp(height, MIN_HEIGHT, window.innerHeight * MAX_SHARE))
    this.js().setAttribute(container, 'style', `--details: ${clamped}px`)
    this.el.setAttribute('aria-valuenow', String(clamped))
    if (save) write(String(clamped))
  }

  private height(): number {
    const pane = this.el.nextElementSibling as HTMLElement | null
    return pane?.offsetHeight ?? MIN_HEIGHT
  }

  private container(): HTMLElement | null {
    return document.getElementById(this.el.dataset.container ?? '')
  }
}

// Storage can be unavailable, as in private windows; the pane then keeps
// its height for the visit only.
const read = (): string | null => {
  try {
    return localStorage.getItem(DETAILS_HEIGHT_KEY)
  } catch {
    return null
  }
}

const write = (value: string): void => {
  try {
    localStorage.setItem(DETAILS_HEIGHT_KEY, value)
  } catch {
    // Kept for this visit only.
  }
}
