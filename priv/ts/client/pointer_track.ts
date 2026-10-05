/**
 * The pointer track's format, shared by the recorder in the browser and
 * the player. Tuples keep batches small; the labels name their fields.
 * PhoenixReplay.Capture.Pointer documents and validates it on the server.
 */

/** A press went down. */
export const DOWN = 0
/** A press came up, or was cancelled. */
export const UP = 1

export const MOUSE = 0
export const TOUCH = 1
export const PEN = 2

export type PressKind = typeof DOWN | typeof UP
export type PointerKind = typeof MOUSE | typeof TOUCH | typeof PEN

/**
 * Where a pointer was. Slot `0` is the mouse or pen; each finger down
 * takes the lowest free slot from `1`.
 */
export type Move = [at: number, x: number, y: number, slot: number]

/**
 * A pointer going down or up. `target` is the id of the pressed element,
 * and `fx`, `fy` the point within it in thousandths, so the player can
 * place the press on the element when the replay lays it out differently.
 */
export type Press = [
  at: number,
  kind: PressKind,
  x: number,
  y: number,
  slot: number,
  type: PointerKind,
  target: string | null,
  fx: number,
  fy: number
]

/** The page's scroll offset. */
export type Scroll = [at: number, x: number, y: number]

/**
 * What the recorder sends: moves and scrolls flattened into one list each.
 * Each `at` counts milliseconds from the batch's first sample, and `span`
 * from that sample to sending the batch.
 */
export interface Batch {
  span: number
  m: number[]
  p: Press[]
  s: number[]
}

/** What the player draws: each `at` counts from the session's start. */
export interface Track {
  moves: Move[]
  presses: Press[]
  scrolls: Scroll[]
}
