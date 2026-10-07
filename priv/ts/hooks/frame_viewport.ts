import { ViewHook } from 'phoenix_live_view'

import {
  type Placement,
  type Shown,
  transform,
  turnBy,
  turnFrames,
  turned,
  TURN_EASING,
  TURN_MS
} from './device_turn'

/** The share of the window's height a fitted frame takes when its box does not set its own. */
const WINDOW_SHARE = 0.75

/**
 * Renders the replay frame at the recorded viewport, keeping its aspect
 * ratio, and turns it as the device was turned.
 *
 * The hook's element carries the recorded size in `data-width` and
 * `data-height`, the screen's orientation angle in `data-angle`, and
 * `data-mode`: `"fit"` scales the frame down until it fits its box,
 * centring it; `"actual"` renders it at 100% inside a box that scrolls. A
 * `[data-frame-overlay]` beside the frame gets the same size and transform,
 * so what it draws lines up with the page.
 *
 * When the recording turns between portrait and landscape, the page takes
 * its new layout at once and turns into place from where the device was,
 * fading in over the layout it replaced, as a phone does; unless motion is
 * reduced. `data-turn` turns the shown device a further 90 degrees, to
 * look at it the other way round; the page keeps the layout it was
 * recorded in.
 *
 * When the box's `--frame-fill` is `1`, the page's layout sizes the box and
 * the frame is scaled to it. Otherwise the box is sized to the scaled
 * frame, which may take `data-max-height`, or a share of the window's height.
 *
 * The sizes are written as rules into the element's `phx-update="ignore"`
 * style element, keyed by the frame's and its box's ids, so LiveView keeps
 * rendering the frame itself; the result is written into
 * `[data-scale-label]`. Without a recorded size the rules are cleared and
 * the frame keeps its own classes.
 */
export class FrameViewport extends ViewHook {
  private observer?: ResizeObserver
  private shown?: Shown
  private placed?: Placement
  private onResize = (): void => this.fit()

  mounted(): void {
    this.observer = new ResizeObserver(this.onResize)
    this.observer.observe(this.el)
    window.addEventListener('resize', this.onResize)
    this.fit()
  }

  updated(): void {
    this.fit()
  }

  destroyed(): void {
    this.observer?.disconnect()
    window.removeEventListener('resize', this.onResize)
  }

  private fit(): void {
    const next: Shown = {
      width: Number(this.el.dataset.width),
      height: Number(this.el.dataset.height),
      angle: Number(this.el.dataset.angle) || 0
    }

    // The new layout starts where the device was, and turns into place.
    const previous = this.shown
    this.shown = next
    if (previous && turned(previous, next) && !reducedMotion()) {
      this.placed = undefined
      this.render(next, -turnBy(previous, next))
      this.render(next, 0, true)
      return
    }

    this.render(next, 0)
  }

  // Draws `shown` turned by `extra` degrees besides the viewer's own turn.
  // A change of turn swings the device there, fading in when its layout
  // changed; anything else eases.
  private render({ width, height }: Shown, extra: number, fades = false): void {
    const style = this.el.querySelector('style')
    const frame = this.el.querySelector('iframe')
    const box = frame?.parentElement
    const label = this.el.querySelector<HTMLElement>('[data-scale-label]')
    if (!style || !frame?.id || !box?.id) return

    if (!width || !height) {
      style.textContent = ''
      if (label) label.textContent = ''
      return
    }

    const degrees = (this.el.dataset.turn === undefined ? 0 : 90) + extra
    const sideways = Math.abs(degrees) % 180 === 90
    const [shownWidth, shownHeight] = sideways ? [height, width] : [width, height]

    const actual = this.el.dataset.mode === 'actual'
    const fills = getComputedStyle(box).getPropertyValue('--frame-fill').trim() === '1'
    const available = this.availableHeight(box, fills)
    const containerWidth = box.clientWidth || this.el.clientWidth

    // Rounded down to whole percents, which keeps text from blurring at odd scales.
    const scale = actual
      ? 1
      : Math.max(
          0.1,
          Math.floor(Math.min(1, containerWidth / shownWidth, available / shownHeight) * 100) / 100
        )

    // A fitted frame does not scroll; a box scrolled at 100% would keep the
    // page shifted out of view once it stops scrolling. The page is held
    // where it was seen, then eases into its fitted place.
    if (!actual && (box.scrollLeft || box.scrollTop))
      this.unscroll(style, frame, box, width, height)

    const boxHeight = actual ? Math.min(shownHeight, available) : Math.round(shownHeight * scale)
    const sized = fills ? '' : `height:${boxHeight}px;`
    // Centred in the box, or from its top left corner when it scrolls. It
    // turns about its centre, so it stays in its place as it turns.
    const left = Math.max(0, (containerWidth - shownWidth * scale) / 2)
    const top = fills ? Math.max(0, (box.clientHeight - shownHeight * scale) / 2) : 0
    const placement: Placement = {
      x: Math.round(left + (shownWidth * scale - width) / 2),
      y: Math.round(top + (shownHeight * scale - height) / 2),
      degrees,
      scale,
      width,
      height,
      roomWidth: containerWidth,
      roomHeight: fills ? box.clientHeight : boxHeight
    }

    const from = this.placed
    const swings = from !== undefined && from.degrees !== degrees && !reducedMotion()
    this.placed = placement

    style.textContent =
      `#${box.id}{${sized}overflow:${actual ? 'auto' : 'hidden'}}` +
      `#${frame.id},#${box.id}>[data-frame-overlay]{width:${width}px;height:${height}px;margin:0;` +
      `transform:${transform(placement)};transform-origin:center}` +
      `@media (prefers-reduced-motion:no-preference){` +
      `#${box.id}{transition:height .2s ease}` +
      `#${frame.id},#${box.id}>[data-frame-overlay]{transition:transform ${swings ? '0s' : '.2s ease'}}}`

    if (swings) {
      const frames = turnFrames(from, placement, fades)
      for (const element of [frame, ...box.querySelectorAll('[data-frame-overlay]')])
        element.animate(frames, { duration: TURN_MS, easing: TURN_EASING })
    }
    if (label) label.textContent = `${width} × ${height} · ${Math.round(scale * 100)}%`
  }

  private unscroll(
    style: HTMLStyleElement,
    frame: HTMLIFrameElement,
    box: HTMLElement,
    width: number,
    height: number
  ): void {
    const { scrollLeft: x, scrollTop: y, clientHeight } = box

    style.textContent =
      `#${box.id}{height:${clientHeight}px;overflow:hidden}` +
      `#${frame.id},#${box.id}>[data-frame-overlay]{width:${width}px;height:${height}px;margin:0;` +
      `transform:translate(${-x}px,${-y}px) rotate(0deg) scale(1);transform-origin:center;transition:none}`

    box.scrollTo(0, 0)
    // Applies the held position before the fitted one replaces it.
    frame.getBoundingClientRect()
  }

  private availableHeight(box: HTMLElement, fills: boolean): number {
    const max = Number(this.el.dataset.maxHeight)
    if (max) return max
    if (fills) return box.clientHeight

    return Math.round(window.innerHeight * WINDOW_SHARE)
  }
}

const reducedMotion = (): boolean => window.matchMedia('(prefers-reduced-motion: reduce)').matches
