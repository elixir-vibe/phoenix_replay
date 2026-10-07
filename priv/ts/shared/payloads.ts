/**
 * What crosses the boundary with the server: the data the browser sends
 * to Elixir and the data Elixir sends to the browser, each typed as the
 * other side reads or writes it.
 *
 * Their keys are the server's, snake_case as Elixir has them, and are not
 * converted: some payloads are keyed by data, such as the keys app code
 * reports state under, form control names and CSS media features, which
 * must arrive as written. So snake_case in this code means "on the wire";
 * a module that uses such a field throughout takes it into a camelCase
 * name where it reads it. The pointer's own track is in `pointer_track`.
 */

/**
 * The browser's viewport, as PhoenixReplay records it: its size and pixel
 * ratio, the screen's orientation angle, and the media settings the page's
 * CSS can see. A setting the browser does not report is left out.
 * Read by `PhoenixReplay.Capture.Browser`.
 */
export interface ReplayViewport {
  width: number
  height: number
  dpr: number
  /** `screen.orientation.angle`: 0, 90, 180 or 270. */
  angle?: number
  color_scheme?: 'light' | 'dark'
  reduced_motion?: boolean
  contrast?: 'more' | 'less' | 'no-preference'
  pointer?: 'coarse' | 'fine' | 'none'
  hover?: 'hover' | 'none'
}

/** What the server asks the browser to record; `null` records none. Sent by `PhoenixReplay.Recorder`. */
export interface RecordSettings {
  pointer: PointerSettings | null
  state: StateSettings | null
}

/** The detail of `phx_replay:start`. */
export interface StartDetail {
  state: StateSettings | null
}

/** The pointer's settings; see the `:pointer` option and `PhoenixReplay.Capture.Pointer`. */
export interface PointerSettings {
  /** Milliseconds between recorded positions of a pointer. */
  sample: number
  /** Milliseconds between recorded scroll offsets. */
  scroll: number
  /** Milliseconds between batches sent. */
  flush: number
  /** Positions, presses and scrolls a batch holds before it is sent early. */
  max_points: number
}

/** Client state's settings; see the `:state` option and `PhoenixReplay.Capture.State`. */
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
  /** Whether the values of form controls are recorded. */
  inputs: boolean
  /** Milliseconds a form control must stay unchanged before its value is recorded. */
  debounce: number
}

/** `dt` counts milliseconds from the batch's first entry. */
export type StateEntry = [dt: number, key: string, changes: Record<string, unknown>]

/** A batch of client state, read by `PhoenixReplay.Capture.State`: `span` counts from the first entry to sending. */
export interface StateBatch {
  span: number
  e: StateEntry[]
}

/** A form control's value: text, whether it is checked, or the options chosen. */
export type InputValue = string | boolean | string[]

/**
 * Form control values, `{selector: {name: value}}`: recorded under
 * `INPUTS_KEY`, and pushed back to the replay frame by
 * `PhoenixReplay.Web.Live.Frame`.
 */
export type InputValues = Record<string, Record<string, InputValue>>

/**
 * The recorded value of each media feature, such as `{ pointer: 'coarse' }`,
 * from `PhoenixReplay.Recording.Client.media/1`.
 */
export type Media = Record<string, string>

/**
 * A replayed moment's root layout, and attributes for `<html>` besides it,
 * pushed as `phx_replay:root` by `PhoenixReplay.Web.Live.Frame`.
 */
export interface Root {
  layout?: string | null
  attributes?: Record<string, string | null>
}

/**
 * The event index and moment an export shows, and the viewport the page
 * had, from `PhoenixReplay.Export.Schedule` through
 * `PhoenixReplay.Export.Screenshots`.
 */
export interface Shot {
  index: number
  at: number
  width: number
  height: number
  media?: Media
}

/** One key combination, such as `["Shift", "ArrowRight"]`, in `KeyboardEvent.key` names. */
export type Combination = string[]

/** A player shortcut, its id and key combinations, from `PhoenixReplay.Web.Player.Shortcuts`. */
export interface Shortcut {
  id: string
  keys: Combination[]
}
