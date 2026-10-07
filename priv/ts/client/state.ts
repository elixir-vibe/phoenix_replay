/**
 * Records state that lives only in the browser.
 *
 * App code reports it with `replayState`:
 *
 *     import { replayState } from "phoenix_replay"
 *
 *     replayState("search", { query: "shoes" })
 *
 * Code that cannot import PhoenixReplay, such as another library,
 * dispatches the same report as a `phx_replay:state` event on `window`:
 *
 *     window.dispatchEvent(
 *       new CustomEvent("phx_replay:state", {
 *         detail: { key: "search", changes: { query: "shoes" } }
 *       })
 *     )
 *
 * `changes` are merged into what was reported under `key` before. Reports
 * are kept whether or not the page is recorded, so a recording starts
 * with the state as it is; while a recorded LiveView asks for it, each
 * report is timestamped and sent in batches as `phx_replay:state`.
 * `replayRecorder` runs all of this.
 */

import type { Push } from './pointer'
import type { StateBatch, StateEntry, StateSettings } from '../shared/payloads'

/** The window event state is reported with. */
export const STATE_EVENT = 'phx_replay:state'

/** What a `phx_replay:state` event carries. */
export interface StateReport {
  /** Names the state, such as a component's id. */
  key: string
  /** A JSON object of fields to merge into the state reported under `key`. */
  changes: Record<string, unknown>
}

type Changes = Record<string, unknown>

/** Reports state under `key`: `changes` are merged into what it held. */
export const replayState = (key: string, changes: Changes, target: Window = window): void => {
  target.dispatchEvent(new CustomEvent(STATE_EVENT, { detail: { key, changes } }))
}

/**
 * Keeps the latest state reported under each key, and hands each report
 * on to a recorder while one is attached.
 */
export class StateStore {
  private readonly latest = new Map<string, Changes>()
  private recorder: StateRecorder | undefined
  private readonly onReport = (event: Event): void =>
    this.report((event as CustomEvent<unknown>).detail)

  constructor(private readonly target: Window) {
    target.addEventListener(STATE_EVENT, this.onReport)
  }

  /** Sends `recorder` the state as it is, then every report until detached. */
  attach(recorder: StateRecorder): void {
    this.recorder = recorder
    for (const [key, changes] of this.latest) recorder.add(key, changes)
  }

  detach(): void {
    this.recorder = undefined
  }

  /** Forgets every key, as when the page leaves a LiveView and its components. */
  clear(): void {
    this.latest.clear()
  }

  close(): void {
    this.target.removeEventListener(STATE_EVENT, this.onReport)
  }

  // The changes are copied now, as their source may change later; anything
  // that is not a key and a JSON object is dropped.
  private report(detail: unknown): void {
    if (!isReport(detail) || detail.key === '') return

    let changes: Changes
    try {
      changes = JSON.parse(JSON.stringify(detail.changes)) as Changes
    } catch {
      return
    }

    this.latest.set(detail.key, { ...this.latest.get(detail.key), ...changes })
    this.recorder?.add(detail.key, changes)
  }
}

const encoder = new TextEncoder()
const bytes = (text: string): number => encoder.encode(text).byteLength

/** Sends the state reported while a recorded LiveView asks for it, in batches. */
export class StateRecorder {
  private entries: StateEntry[] = []
  private size = 0
  private started = 0
  private readonly timer: ReturnType<typeof setInterval>
  private readonly onHidden = (): void => {
    if (this.target.document.hidden) this.flush()
  }

  constructor(
    private readonly push: Push,
    private readonly target: Window,
    private readonly settings: StateSettings
  ) {
    target.document.addEventListener('visibilitychange', this.onHidden)
    this.timer = setInterval(() => this.flush(), settings.flush)
  }

  stop(): void {
    this.flush()
    clearInterval(this.timer)
    this.target.document.removeEventListener('visibilitychange', this.onHidden)
  }

  /** Adds an entry, unless its key or changes are over the limits. */
  add(key: string, changes: Changes): void {
    if (bytes(key) > this.settings.max_key) return

    const size = bytes(JSON.stringify(changes))
    if (size > this.settings.max_entry_bytes) return
    if (this.size + size > this.settings.max_bytes) this.flush()
    if (this.entries.length === 0) this.started = performance.now()

    this.entries.push([Math.round(performance.now() - this.started), key, changes])
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
