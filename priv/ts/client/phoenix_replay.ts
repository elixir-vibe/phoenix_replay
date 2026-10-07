/**
 * Client context for PhoenixReplay: the browser's viewport and a per-tab id,
 * sent with LiveView's connect params and its event metadata.
 *
 *     import { replayParams, replayMetadata } from "phoenix_replay"
 *
 *     const liveSocket = new LiveSocket("/live", Socket, {
 *       params: () => ({ _csrf_token: csrfToken, ...replayParams() }),
 *       metadata: replayMetadata
 *     })
 *
 * Both are optional: without them, recordings simply carry no viewport.
 *
 * `replayRecorder(liveSocket)` also records the pointer, touches and
 * scrolling for LiveViews that configure `:pointer`, what is typed into
 * form controls, and state reported with `replayState(key, changes)`; see
 * `./recorder`.
 */

import type { ReplayViewport } from '../shared/payloads'
import { viewport } from './viewport'

export { RECORDING_ATTRIBUTE, replayRecorder, START_EVENT, STOP_EVENT } from './recorder'
export type { RecorderSocket } from './recorder'
export { IGNORE_ATTRIBUTE, INPUTS_KEY } from './inputs'
export { replayState, STATE_EVENT } from './state'
export type { StateReport } from './state'
export type {
  PointerSettings,
  RecordSettings,
  ReplayViewport,
  StartDetail,
  StateSettings
} from '../shared/payloads'

const TAB_KEY = 'phoenix_replay:tab'

const randomId = (): string =>
  typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : Array.from(crypto.getRandomValues(new Uint8Array(16)), (b) =>
        b.toString(16).padStart(2, '0')
      ).join('')

/**
 * Returns an id for this browser tab, kept in sessionStorage so it survives
 * navigation and reloads within the tab. Returns an empty string when
 * storage is unavailable.
 */
export const tabId = (): string => {
  try {
    const existing = sessionStorage.getItem(TAB_KEY)
    if (existing) return existing

    const id = randomId()
    sessionStorage.setItem(TAB_KEY, id)
    return id
  } catch {
    return ''
  }
}

/** Connect params to merge into LiveSocket's `params`. */
export const replayParams = (): { _replay: ReplayViewport & { tab: string } } => ({
  _replay: { ...viewport(), tab: tabId() }
})

const withViewport = (): { _replay: ReplayViewport } => ({ _replay: viewport() })

/**
 * Event metadata for LiveSocket's `metadata` option. The viewport travels
 * with each click and key press, so the recording follows resizes. Merge it
 * into your own metadata functions if you have some.
 */
export const replayMetadata = {
  click: withViewport,
  keydown: withViewport,
  keyup: withViewport
}
