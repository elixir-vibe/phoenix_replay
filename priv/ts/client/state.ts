/**
 * Records state that lives only in the browser, which any code reports by
 * dispatching a `phx_replay:state` event on `window`, needing no import:
 *
 *     window.dispatchEvent(
 *       new CustomEvent("phx_replay:state", {
 *         detail: { key: "search", changes: { query: "shoes" } }
 *       })
 *     )
 *
 * `changes` are merged into what was recorded under `key` before. Entries
 * are timestamped and sent in batches as `phx_replay:state` while a
 * recorded LiveView asks for it; `replayRecorder` starts and stops this.
 */

import type { Push } from './pointer'

/** The window event code in the browser reports state with. */
export const STATE_EVENT = 'phx_replay:state'

/** What a `phx_replay:state` event carries. */
export interface StateReport {
  /** Names the state, such as a component's id. */
  key: string
  /** A JSON object of fields to merge into the state recorded under `key`. */
  changes: Record<string, unknown>
}

/** The settings the server sends; see the `:state` option. */
export interface StateSettings {
  /** Milliseconds between batches sent. */
  flush: number
  /** Entries a batch holds before it is sent early. */
  max_entries: number
  /** Bytes a key may have. */
  max_key: number
  /** The JSON size an entry's changes may have; larger ones are dropped. */
  max_entry_bytes: number
  /** The JSON size a batch holds before it is sent early. */
  max_bytes: number
}

/** `dt` counts milliseconds from the batch's first entry. */
export type StateEntry = [dt: number, key: string, changes: Record<string, unknown>]

/** What is sent: `span` counts from the first entry to sending. */
export interface StateBatch {
  span: number
  e: StateEntry[]
}

const encoder = new TextEncoder()
const bytes = (text: string): number => encoder.encode(text).byteLength

/** Records reported state until stopped. */
export class StateRecorder {
  private entries: StateEntry[] = []
  private size = 0
  private started = 0
  private readonly timer: ReturnType<typeof setInterval>
  private readonly onReport = (event: Event): void =>
    this.report((event as CustomEvent<unknown>).detail)
  private readonly onHidden = (): void => {
    if (this.target.document.hidden) this.flush()
  }

  constructor(
    private readonly push: Push,
    private readonly target: Window,
    private readonly settings: StateSettings
  ) {
    target.addEventListener(STATE_EVENT, this.onReport)
    target.document.addEventListener('visibilitychange', this.onHidden)
    this.timer = setInterval(() => this.flush(), settings.flush)
  }

  stop(): void {
    this.flush()
    clearInterval(this.timer)
    this.target.removeEventListener(STATE_EVENT, this.onReport)
    this.target.document.removeEventListener('visibilitychange', this.onHidden)
  }

  // Anything that is not a key and a JSON object within the limits is
  // dropped. The changes are copied now, as their source may change later.
  private report(detail: unknown): void {
    if (!isReport(detail)) return

    const { key, changes } = detail
    if (key === '' || bytes(key) > this.settings.max_key) return

    let json: string
    try {
      json = JSON.stringify(changes)
    } catch {
      return
    }

    const size = bytes(json)
    if (size > this.settings.max_entry_bytes) return
    if (this.size + size > this.settings.max_bytes) this.flush()
    if (this.entries.length === 0) this.started = performance.now()

    const dt = Math.round(performance.now() - this.started)
    this.entries.push([dt, key, JSON.parse(json) as Record<string, unknown>])
    this.size += size

    if (this.entries.length >= this.settings.max_entries) this.flush()
  }

  private flush(): void {
    if (this.entries.length === 0) return

    const batch: StateBatch = {
      span: Math.round(performance.now() - this.started),
      e: this.entries
    }

    this.entries = []
    this.size = 0
    this.push(STATE_EVENT, batch)
  }
}

const isReport = (detail: unknown): detail is StateReport => {
  if (typeof detail !== 'object' || detail === null) return false
  const { key, changes } = detail as Partial<StateReport>
  return (
    typeof key === 'string' &&
    typeof changes === 'object' &&
    changes !== null &&
    !Array.isArray(changes)
  )
}
