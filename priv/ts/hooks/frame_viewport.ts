import { ViewHook } from 'phoenix_live_view'

/** Space kept below the frame when fitting it to the window, in pixels. */
const BOTTOM_GAP = 24
/** The smallest height a fitted frame is given, however short the window. */
const MIN_HEIGHT = 320

/**
 * Renders the replay frame at the recorded viewport, keeping its aspect
 * ratio.
 *
 * The hook's element carries the recorded size in `data-width` and
 * `data-height`, and `data-mode`: `"fit"` scales the frame down until both
 * dimensions fit the element's width and the window's height below it,
 * centring narrower devices; `"actual"` renders it at 100% inside a box
 * that scrolls. `data-max-height` caps the height instead of the window.
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
    const available = this.availableHeight(box)
    const containerWidth = box.clientWidth || this.el.clientWidth

    // Rounded down to whole percents, which keeps text from blurring at odd scales.
    const scale = actual
      ? 1
      : Math.max(
          0.1,
          Math.floor(Math.min(1, containerWidth / width, available / height) * 100) / 100
        )

    const inset = Math.max(0, Math.round((containerWidth - width * scale) / 2))
    const boxHeight = actual ? Math.min(height, available) : Math.round(height * scale)

    // A rotated device eases into its new size, unless motion is reduced.
    style.textContent =
      `#${box.id}{height:${boxHeight}px;overflow:${actual ? 'auto' : 'hidden'}}` +
      `#${frame.id}{width:${width}px;height:${height}px;margin-left:${inset}px;` +
      `transform:scale(${scale});transform-origin:top left}` +
      `@media (prefers-reduced-motion:no-preference){` +
      `#${box.id}{transition:height .2s ease}` +
      `#${frame.id}{transition:transform .2s ease,margin-left .2s ease}}`

    if (label) label.textContent = `${width} × ${height} · ${Math.round(scale * 100)}%`
  }

  private availableHeight(box: HTMLElement): number {
    const max = Number(this.el.dataset.maxHeight)
    if (max) return max

    const top = box.getBoundingClientRect().top + window.scrollY
    return Math.max(MIN_HEIGHT, window.innerHeight - top - BOTTOM_GAP)
  }
}
