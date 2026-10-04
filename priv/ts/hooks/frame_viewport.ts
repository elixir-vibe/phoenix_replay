import { ViewHook } from 'phoenix_live_view'

/**
 * Renders the replay frame at the recorded viewport, scaled down to fit.
 *
 * The hook's element carries the recorded size in `data-width` and
 * `data-height`. The sizes are written as rules into its
 * `phx-update="ignore"` style element, keyed by the frame's and its box's
 * ids, so LiveView keeps rendering the frame itself. Without a recorded
 * size the rules are cleared and the frame keeps its own classes.
 */
export class FrameViewport extends ViewHook {
  private observer?: ResizeObserver

  mounted(): void {
    this.observer = new ResizeObserver(() => this.fit())
    this.observer.observe(this.el)
    this.fit()
  }

  updated(): void {
    this.fit()
  }

  destroyed(): void {
    this.observer?.disconnect()
  }

  private fit(): void {
    const style = this.el.querySelector('style')
    const frame = this.el.querySelector('iframe')
    const box = frame?.parentElement
    if (!style || !frame?.id || !box?.id) return

    const width = Number(this.el.dataset.width)
    const height = Number(this.el.dataset.height)

    if (!width || !height) {
      style.textContent = ''
      return
    }

    const scale = Math.min(1, this.el.clientWidth / width)

    // A narrower viewport is centered, like a device on a desk.
    const inset = Math.max(0, (this.el.clientWidth - width) / 2)

    style.textContent =
      `#${box.id}{height:${Math.round(height * scale)}px}` +
      `#${frame.id}{width:${width}px;height:${height}px;margin-left:${inset}px;` +
      `transform:scale(${scale});transform-origin:top left}`
  }
}
