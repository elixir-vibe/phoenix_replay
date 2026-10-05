import { ViewHook } from 'phoenix_live_view'

import { TIME_EVENT } from './scrubber'

/** How long a seek may take to render before the export gives up, in milliseconds. */
const SHOWN_TIMEOUT_MS = 15_000

/** The event index and moment to show, and the viewport the page had. */
export interface Shot {
  index: number
  at: number
  width: number
  height: number
}

declare global {
  interface Window {
    phoenixReplayStage?: { show: (shot: Shot) => Promise<void> }
  }
}

/**
 * The stage video exports film: sizes and centres the replay frame, waits
 * until the frame shows the event it was sought to, and moves the pointer
 * overlay to the moment.
 *
 * The element holds the frame's box, with the iframe and the
 * `[data-frame-overlay]` in it. The frame pushes `phx_replay:shown` with
 * the index after each render; the export seeks it over the player
 * channel, then calls `window.phoenixReplayStage.show` and takes the
 * screenshot once it resolves.
 */
export class ExportStage extends ViewHook {
  private shown = -1
  private waiting: { index: number; resolve: () => void } | null = null

  mounted(): void {
    const frame = this.el.querySelector('iframe')
    const listen = (): void =>
      frame?.contentWindow?.addEventListener('phx:phx_replay:shown', (event) => {
        this.onShown((event as CustomEvent<{ index: number }>).detail.index)
      })

    // The frame may have loaded before the stage's LiveView connected.
    if (
      frame?.contentDocument?.readyState === 'complete' &&
      frame.contentWindow?.location.href !== 'about:blank'
    )
      listen()
    frame?.addEventListener('load', listen)

    window.phoenixReplayStage = { show: (shot) => this.show(shot) }
  }

  destroyed(): void {
    delete window.phoenixReplayStage
  }

  async show({ index, at, width, height }: Shot): Promise<void> {
    const device = this.el.firstElementChild as HTMLElement | null
    if (!device) return

    device.style.width = `${width}px`
    device.style.height = `${height}px`
    device.style.left = `${Math.max(0, Math.round((this.el.clientWidth - width) / 2))}px`
    device.style.top = `${Math.max(0, Math.round((this.el.clientHeight - height) / 2))}px`

    const overlay = device.querySelector<HTMLElement>('[data-frame-overlay]')
    if (overlay) {
      overlay.dataset.width = String(width)
      overlay.dataset.height = String(height)
    }

    await this.until(index)
    window.dispatchEvent(new CustomEvent(TIME_EVENT, { detail: at }))
    // Two frames: one for the page to lay out, one for it to paint.
    await nextFrame()
    await nextFrame()
  }

  private onShown(index: number): void {
    this.shown = index
    if (this.waiting?.index === index) this.waiting.resolve()
  }

  private until(index: number): Promise<void> {
    if (this.shown === index) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`the frame did not show event ${index}`)),
        SHOWN_TIMEOUT_MS
      )

      this.waiting = {
        index,
        resolve: () => {
          clearTimeout(timer)
          this.waiting = null
          resolve()
        }
      }
    })
  }
}

const nextFrame = (): Promise<void> =>
  new Promise((resolve) => requestAnimationFrame(() => resolve()))
