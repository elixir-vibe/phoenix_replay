import { autoUpdate, computePosition, flip, offset, shift, type Placement } from '@floating-ui/dom'
import { ViewHook } from 'phoenix_live_view'

/** How far a floating element sits from its anchor, and from the window's edges. */
const GAP = 6
const PADDING = 8

/**
 * Where `floating` goes next to `anchor`: on the side `placement` asks,
 * else the opposite one when it does not fit, kept inside the window.
 * Positions are fixed, so no scrolling or clipping container cuts it off.
 */
export const place = async (
  anchor: Element,
  floating: HTMLElement,
  placement: Placement
): Promise<{ x: number; y: number }> => {
  const { x, y } = await computePosition(anchor, floating, {
    placement,
    strategy: 'fixed',
    middleware: [offset(GAP), flip(), shift({ padding: PADDING })]
  })

  return { x: Math.round(x), y: Math.round(y) }
}

const placementOf = (el: HTMLElement, fallback: Placement): Placement =>
  (el.dataset.placement as Placement | undefined) ?? fallback

/**
 * Positions the tooltip of any `[data-tip]` element as the pointer or the
 * keyboard reaches it, and marks it `data-placed`; CSS shows it once
 * placed, so it never shows where it was not put. See
 * `PhoenixReplay.Web.Components.Core.tooltip/1`.
 */
export const floatingTooltips = (target: Window): void => {
  const show = (event: Event): void => {
    const anchor = event.target instanceof Element ? event.target.closest('[data-tip]') : null
    const tip = anchor?.querySelector<HTMLElement>(':scope > [data-tip-content]')
    if (!anchor || !tip) return

    place(anchor, tip, placementOf(tip, 'top'))
      .then(({ x, y }) => {
        tip.style.left = `${x}px`
        tip.style.top = `${y}px`
        tip.dataset.placed = ''
      })
      .catch(() => undefined)
  }

  target.addEventListener('pointerover', show)
  target.addEventListener('focusin', show)
}

/**
 * Keeps a menu or picker next to the element `data-anchor` names, on the
 * side `data-placement` asks, while it is shown and as the page scrolls
 * or resizes. The position is set through the hook's `js()`, so
 * LiveView's patches leave it in place.
 */
export class Floating extends ViewHook {
  private cleanup: (() => void) | null = null

  mounted(): void {
    const anchor = document.getElementById(this.el.dataset.anchor ?? '')
    if (!anchor) return

    const update = (): void => {
      place(anchor, this.el, placementOf(this.el, 'bottom-start'))
        .then(({ x, y }) => this.js().setAttribute(this.el, 'style', `left: ${x}px; top: ${y}px`))
        .catch(() => undefined)
    }

    this.cleanup = autoUpdate(anchor, this.el, update)
  }

  destroyed(): void {
    this.cleanup?.()
  }
}
