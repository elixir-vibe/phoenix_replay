import { ViewHook } from 'phoenix_live_view'

/** The share of the window's height a fitted frame takes when its box does not set its own. */
const WINDOW_SHARE = 0.75

/**
 * Renders the replay frame at the recorded viewport, keeping its aspect
 * ratio.
 *
 * The hook's element carries the recorded size in `data-width` and
 * `data-height`, and `data-mode`: `"fit"` scales the frame down until both
 * dimensions fit the element's width and the window's height below it,
 * centring narrower devices; `"actual"` renders it at 100% inside a box
 * that scrolls. A `[data-frame-overlay]` beside the frame gets its size,
 * scale and position too, so what it draws lines up with the page.
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
    const style = this.el.querySelector('style')
    const frame = this.el.querySelector('iframe')
    const box = frame?.parentElement
    const label = this.el.querySelector<HTMLElement>('[data-scale-label]')
    if (!style || !frame?.id || !box?.id) return

    const width = Number(this.el.dataset.width)
    const height = Number(this.el.dataset.height)

    if (!width || !height) {
      style.textContent = ''
      if (label) label.textContent = ''
      return
    }

    const actual = this.el.dataset.mode === 'actual'
    const fills = getComputedStyle(box).getPropertyValue('--frame-fill').trim() === '1'
    const available = this.availableHeight(box, fills)
    const containerWidth = box.clientWidth || this.el.clientWidth

    // Rounded down to whole percents, which keeps text from blurring at odd scales.
    const scale = actual
      ? 1
      : Math.max(
          0.1,
          Math.floor(Math.min(1, containerWidth / width, available / height) * 100) / 100
        )

    // A fitted frame does not scroll; a box scrolled at 100% would keep the
    // page shifted out of view once it stops scrolling. The page is held
    // where it was seen, then eases into its fitted place.
    if (!actual && (box.scrollLeft || box.scrollTop))
      this.unscroll(style, frame, box, width, height)

    const inset = Math.max(0, Math.round((containerWidth - width * scale) / 2))
    const boxHeight = actual ? Math.min(height, available) : Math.round(height * scale)
    const sized = fills ? '' : `height:${boxHeight}px;`

    // A rotated device eases into its new size, unless motion is reduced.
    style.textContent =
      `#${box.id}{${sized}overflow:${actual ? 'auto' : 'hidden'}}` +
      `#${frame.id},#${box.id}>[data-frame-overlay]{width:${width}px;height:${height}px;margin-left:${inset}px;` +
      `transform:translate(0px,0px) scale(${scale});transform-origin:top left}` +
      `@media (prefers-reduced-motion:no-preference){` +
      `#${box.id}{transition:height .2s ease}` +
      `#${frame.id},#${box.id}>[data-frame-overlay]{transition:transform .2s ease,margin-left .2s ease}}`

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
      `#${frame.id},#${box.id}>[data-frame-overlay]{width:${width}px;height:${height}px;margin-left:0;` +
      `transform:translate(${-x}px,${-y}px) scale(1);transform-origin:top left;transition:none}`

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
