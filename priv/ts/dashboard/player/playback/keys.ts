import { ViewHook } from 'phoenix_live_view'
import type { Combination, Shortcut } from '../../../shared/payloads'

/** What a shortcut does: an event pushed to the player, or a click on a control. */
type Action = { push: string; payload?: Record<string, unknown> } | { click: string }

const ACTIONS: Record<string, Action> = {
  toggle: { push: 'toggle' },
  previous: { push: 'previous' },
  next: { push: 'next' },
  back: { push: 'skip', payload: { by: -5_000 } },
  forward: { push: 'skip', payload: { by: 5_000 } },
  start: { push: 'jump', payload: { to: 'start' } },
  end: { push: 'jump', payload: { to: 'end' } },
  next_error: { push: 'error', payload: { direction: 'next' } },
  previous_error: { push: 'error', payload: { direction: 'previous' } },
  next_mark: { push: 'mark', payload: { direction: 'next' } },
  previous_mark: { push: 'mark', payload: { direction: 'previous' } },
  speed_1: { push: 'speed', payload: { value: '1' } },
  speed_2: { push: 'speed', payload: { value: '2' } },
  speed_5: { push: 'speed', payload: { value: '5' } },
  speed_10: { push: 'speed', payload: { value: '10' } },
  fit: { push: 'toggle_frame_mode' },
  rotate: { push: 'rotate' },
  pointer: { click: '#replay-pointer-switch' },
  help: { push: 'shortcuts' }
}

/** Shortcuts a held key repeats: stepping and skipping. The rest act once per press. */
const REPEATABLE = new Set(['previous', 'next', 'back', 'forward'])

/** Where keys are typed, never taken. */
const EDITABLE = 'input, textarea, select, [contenteditable]:not([contenteditable="false"])'

/** An open dialog, which has the keyboard to itself. */
const MODAL = '[aria-modal="true"]'

/** Controls the space bar presses itself. */
const PRESSABLE =
  'button, a[href], summary, [role="button"], [role="switch"], [role="tab"], [role^="menuitem"]'

/**
 * Whether `event` is `combination`. Letters and named keys need Shift
 * exactly as the combination has it; a symbol such as `?` comes with
 * whatever its keyboard layout needs.
 */
export const matches = (combination: Combination, event: KeyboardEvent): boolean => {
  const key = combination[combination.length - 1] ?? ''
  const pressed = event.key === ' ' ? 'Space' : event.key
  if (pressed.toLowerCase() !== key.toLowerCase()) return false

  const symbol = key.length === 1 && !/[a-z0-9]/i.test(key)
  return symbol || event.shiftKey === combination.includes('Shift')
}

/** The shortcut `event` is, if any, among `shortcuts`. */
export const shortcutFor = (shortcuts: Shortcut[], event: KeyboardEvent): Shortcut | undefined =>
  shortcuts.find(({ keys }) => keys.some((combination) => matches(combination, event)))

/**
 * Acts on the player's keyboard shortcuts anywhere on the page, from the
 * list in `data-shortcuts` (see `PhoenixReplay.Web.Player.Shortcuts`).
 *
 * Keys are left alone while a dialog is open, while typing in a field,
 * with Control, Command or Alt held, when something already handled them, such as the timeline's
 * own arrows, and for the space bar on a control that presses with it.
 * `/` is the search's own shortcut; see `dom/shortcut`.
 */
export class PlayerKeys extends ViewHook {
  private shortcuts: Shortcut[] = []
  private readonly onKeyDown = (event: KeyboardEvent): void => this.handle(event)

  mounted(): void {
    this.shortcuts = JSON.parse(this.el.dataset.shortcuts ?? '[]') as Shortcut[]
    window.addEventListener('keydown', this.onKeyDown)
  }

  destroyed(): void {
    window.removeEventListener('keydown', this.onKeyDown)
  }

  private handle(event: KeyboardEvent): void {
    if (event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey) return
    if (document.querySelector(MODAL)) return

    const target = event.target instanceof Element ? event.target : null
    if (target?.closest(EDITABLE)) return
    if (event.key === ' ' && target?.closest(PRESSABLE)) return

    const shortcut = shortcutFor(this.shortcuts, event)
    const action = shortcut && ACTIONS[shortcut.id]
    if (!shortcut || !action) return
    if (event.repeat && !REPEATABLE.has(shortcut.id)) return

    event.preventDefault()

    if ('click' in action) {
      const control = document.querySelector<HTMLElement>(action.click)
      if (control && !control.hasAttribute('disabled')) control.click()
    } else {
      this.pushEvent(action.push, action.payload ?? {}).catch(() => undefined)
    }
  }
}
