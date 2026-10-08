/**
 * Records what only the browser knows for PhoenixReplay: the pointer,
 * touches and scrolling, what is typed and chosen in form controls, and
 * state that code in the page reports with `replayState`.
 *
 *     import { replayRecorder } from "phoenix_replay"
 *
 *     replayRecorder(liveSocket)
 *
 * Nothing is sent until a recorded LiveView mounts and says what to
 * record. Reported state is kept until then, so a recording starts with
 * the state as it is; code that reports it needs to know nothing about
 * recording. See `./state` and `./inputs`.
 *
 * Recording ends when the page leaves the LiveView, by navigating to
 * another, which starts again if it is recorded too, or by losing its
 * connection, after which the rejoined view starts again. `window` gets
 * `phx_replay:start`, with `{ state: StateSettings | null }`, and
 * `phx_replay:stop`, and `<html>` carries a `data-phx-replay` attribute
 * holding the start detail as JSON while recording, for code that wants
 * to know.
 *
 * Batches go back over the LiveView socket as events PhoenixReplay's
 * recorder takes before the view sees them.
 */

import { InputRecorder } from './inputs'
import { replayInputs } from '../replay/inputs'
import { replayRoot } from '../replay/root'
import type { RecordSettings, StartDetail } from '../shared/payloads'
import { PointerRecorder, type Push } from './pointer'
import { StateRecorder, StateStore } from './state'
import { ViewportRecorder } from './viewport'

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
  // Kept whether or not the page is recorded, so recording starts with the
  // state as it is and reporters never need to know when it starts.
  const store = new StateStore(target)

  const push: Push = (event, value) => {
    const main = target.document.querySelector('[data-phx-main]')
    if (main) liveSocket.execJS(main, JSON.stringify([['push', { event, value }]]))
  }

  const stop = (): void => {
    if (!recorders) return
    for (const recorder of recorders) recorder.stop()
    store.detach()
    recorders = undefined
    target.document.documentElement.removeAttribute(RECORDING_ATTRIBUTE)
    target.dispatchEvent(new CustomEvent(STOP_EVENT))
  }

  const start = (event: Event): void => {
    stop()
    const { pointer, state } = (event as CustomEvent<Partial<RecordSettings>>).detail ?? {}

    recorders = [new ViewportRecorder(push, target)]
    if (pointer) recorders.push(new PointerRecorder(push, target, pointer))

    if (state) {
      const recorder = new StateRecorder(push, target, state)
      store.attach(recorder)
      // Inputs stop before the state recorder, so their last changes go out.
      if (state.inputs) recorders.push(new InputRecorder(target, state.debounce))
      recorders.push(recorder)
    }

    const detail: StartDetail = { state: state ?? null }
    target.document.documentElement.setAttribute(RECORDING_ATTRIBUTE, JSON.stringify(detail))
    target.dispatchEvent(new CustomEvent(START_EVENT, { detail }))
  }

  const leave = (event: Event): void => {
    const kind = (event as CustomEvent<{ kind?: string }>).detail?.kind
    if (kind !== undefined && SAME_VIEW.has(kind)) return

    stop()
    // Navigating to another LiveView leaves its components, and their state, behind.
    if (kind === 'redirect') store.clear()
  }

  target.addEventListener(`phx:${RECORD_EVENT}`, start)
  target.addEventListener('phx:page-loading-start', leave)
  // In a replay frame rendered in the app's own layout, the app's script is
  // the one that puts recorded form values and root attributes back.
  const stopRestoring = replayInputs(target)
  const stopRooting = replayRoot(target)

  return () => {
    stop()
    store.close()
    stopRestoring()
    stopRooting()
    target.removeEventListener(`phx:${RECORD_EVENT}`, start)
    target.removeEventListener('phx:page-loading-start', leave)
  }
}
