import { ViewHook } from 'phoenix_live_view'

import { applyMedia, type Media } from '../dom/media'
import { TIME_EVENT } from './scrubber'

/** How long a seek may take to render before the export gives up, in milliseconds. */
const SHOWN_TIMEOUT_MS = 15_000

/** The event index and moment to show, and the viewport the page had. */
export interface Shot {
  index: number
  at: number
  width: number
  height: number
  media?: Media
}

declare global {
  interface Window {
    phoenixReplayStage?: { ready: () => Promise<void>; show: (shot: Shot) => Promise<void> }
  }
}

/**
 * The stage video exports film: sizes and centres the replay frame, has
 * the stage seek it, waits until it shows that event, and moves the
 * pointer overlay to the moment.
 *
 * The element holds the frame's box, with the iframe and the
 * `[data-frame-overlay]` in it. The stage announces the frame with
 * `phx_replay:frame_ready` once its LiveView connects; the frame pushes
 * `phx_replay:shown` with the index after each render. The export calls
 * `window.phoenixReplayStage.ready`, then `show` for each moment, and
 * takes the screenshot once it resolves.
 */
export class ExportStage extends ViewHook {
  private shown = -1
  private sought: number | undefined
  private waiting: { index: number; resolve: () => void } | null = null
  private listening: Window | null = null
  private frameReady!: Promise<void>

  mounted(): void {
    // The frame's LiveView has connected, so its document is the one that
    // will show events; a reload makes a new one, heard on its load.
    this.frameReady = new Promise((resolve) => {
      this.handleEvent('phx_replay:frame_ready', () => {
        this.listen()
        resolve()
      })
    })

    this.el.querySelector('iframe')?.addEventListener('load', () => this.listen())
    window.phoenixReplayStage = { ready: () => this.frameReady, show: (shot) => this.show(shot) }
  }

  destroyed(): void {
    delete window.phoenixReplayStage
  }

  async show({ index, at, width, height, media }: Shot): Promise<void> {
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

    if (index !== this.sought) {
      this.sought = index
      this.pushEvent('seek', { index }).catch(() => undefined)
    }

    await this.until(index)
    applyMedia(this.el.querySelector('iframe')?.contentDocument, media)
    window.dispatchEvent(new CustomEvent(TIME_EVENT, { detail: at }))
    // Two frames: one for the page to lay out, one for it to paint.
    await nextFrame()
    await nextFrame()
  }

  private listen(): void {
    const page = this.el.querySelector('iframe')?.contentWindow ?? null
    if (!page || page === this.listening) return

    this.listening = page
    page.addEventListener('phx:phx_replay:shown', (event) => {
      this.onShown((event as CustomEvent<{ index: number }>).detail.index)
    })
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
