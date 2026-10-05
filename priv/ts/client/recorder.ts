/**
 * Records what only the browser knows for PhoenixReplay: the pointer,
 * touches and scrolling, and state that code in the page reports.
 *
 *     import { replayRecorder } from "phoenix_replay"
 *
 *     replayRecorder(liveSocket)
 *
 * Nothing is recorded until a recorded LiveView mounts and sends what to
 * record. It then dispatches `phx_replay:start` on `window`, with the
 * state settings as its detail, `{ state: StateSettings | null }`, and
 * `phx_replay:stop` when recording ends: when the page leaves the
 * LiveView, by navigating to another, which starts again if it is
 * recorded too, or by losing its connection, after which the rejoined
 * view starts again. While recording, `<html>` carries a
 * `data-phx-replay` attribute holding the start detail as JSON, for code
 * that loads later. Other code can use either without importing this
 * module, to report its state; see `./state`.
 *
 * Batches go back over the LiveView socket as events PhoenixReplay's
 * recorder takes before the view sees them.
 */

import { type PointerSettings, PointerRecorder, type Push } from './pointer'
import { type StateSettings, StateRecorder } from './state'

/** Dispatched on `window` when recording starts. */
export const START_EVENT = 'phx_replay:start'
/** Dispatched on `window` when recording stops. */
export const STOP_EVENT = 'phx_replay:stop'

/** Set on `<html>` while recording, to the start detail as JSON. */
export const RECORDING_ATTRIBUTE = 'data-phx-replay'

const RECORD_EVENT = 'phx_replay:record'

// The page-loading kinds that stay on the same LiveView: a patch, and an
// event pushed with page loading. Any other leaves it or rejoins it.
const SAME_VIEW = new Set(['patch', 'element'])

/** What the server asks the browser to record; `null` records none. */
export interface RecordSettings {
  pointer: PointerSettings | null
  state: StateSettings | null
}

/** The detail of `phx_replay:start`. */
export interface StartDetail {
  state: StateSettings | null
}

/** The part of LiveSocket replayRecorder uses. */
export interface RecorderSocket {
  execJS(el: Element, encodedJS: string, eventType?: string | null): void
}

/**
 * Records while a LiveView asks for it, and returns a function that stops
 * listening altogether.
 */
export const replayRecorder = (
  liveSocket: RecorderSocket,
  target: Window = window
): (() => void) => {
  let recorders: { stop(): void }[] | undefined

  const push: Push = (event, value) => {
    const main = target.document.querySelector('[data-phx-main]')
    if (main) liveSocket.execJS(main, JSON.stringify([['push', { event, value }]]))
  }

  const stop = (): void => {
    if (!recorders) return
    for (const recorder of recorders) recorder.stop()
    recorders = undefined
    target.document.documentElement.removeAttribute(RECORDING_ATTRIBUTE)
    target.dispatchEvent(new CustomEvent(STOP_EVENT))
  }

  const start = (event: Event): void => {
    stop()
    const { pointer, state } = (event as CustomEvent<Partial<RecordSettings>>).detail ?? {}

    recorders = [
      ...(pointer ? [new PointerRecorder(push, target, pointer)] : []),
      ...(state ? [new StateRecorder(push, target, state)] : [])
    ]

    const detail: StartDetail = { state: state ?? null }
    target.document.documentElement.setAttribute(RECORDING_ATTRIBUTE, JSON.stringify(detail))
    target.dispatchEvent(new CustomEvent(START_EVENT, { detail }))
  }

  const leave = (event: Event): void => {
    const kind = (event as CustomEvent<{ kind?: string }>).detail?.kind
    if (kind === undefined || !SAME_VIEW.has(kind)) stop()
  }

  target.addEventListener(`phx:${RECORD_EVENT}`, start)
  target.addEventListener('phx:page-loading-start', leave)

  return () => {
    stop()
    target.removeEventListener(`phx:${RECORD_EVENT}`, start)
    target.removeEventListener('phx:page-loading-start', leave)
  }
}
