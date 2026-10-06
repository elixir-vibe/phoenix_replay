import { type InputValues, restoreInputs } from './inputs'

/** The event the replay frame receives the recorded form values with. */
export const INPUTS_EVENT = 'phx:phx_replay:inputs'

/**
 * Puts the recorded form control values back into the replayed page after
 * each render, as the server pushes them, and returns a function that
 * stops. See `PhoenixReplay.Web.Live.Frame`.
 *
 * The replay frame runs the dashboard's script by default, and the app's
 * own when it renders in the app's root layout (`:frame_layout`); both
 * call this, so either way the values come back.
 */
export const replayInputs = (target: Window): (() => void) => {
  let restored = new Set<string>()

  const restore = (event: Event): void => {
    const { values } = (event as CustomEvent<{ values?: InputValues }>).detail ?? {}
    restored = restoreInputs(target.document, values ?? {}, restored)
  }

  target.addEventListener(INPUTS_EVENT, restore)
  return () => target.removeEventListener(INPUTS_EVENT, restore)
}
