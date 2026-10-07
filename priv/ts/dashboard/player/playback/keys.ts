import { ViewHook } from 'phoenix_live_view'
import { createKeybindingsHandler } from 'tinykeys'
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
 * A combination in tinykeys' notation, such as `Shift+E`. Letters and
 * named keys need Shift exactly as the combination has it; a lone symbol,
 * such as `?`, comes with or without it, as its keyboard layout needs.
 */
export const binding = (combination: Combination): string => {
  const [key = ''] = combination.slice(-1)
  const symbol = combination.length === 1 && key.length === 1 && !/[a-z0-9]/i.test(key)
  return symbol ? `[Shift]+${key}` : combination.join('+')
}

/**
 * Acts on the player's keyboard shortcuts anywhere on the page, from the
 * list in `data-shortcuts` (see `PhoenixReplay.Web.Player.Shortcuts`),
 * matched by [tinykeys](https://github.com/jamiebuilds/tinykeys), which
 * also leaves combinations with a modifier they do not name alone.
 *
 * Keys are left alone while a dialog is open, while typing in a field,
 * when something already handled them, such as the timeline's own arrows,
 * and for the space bar on a control that presses with it. A held key
 * repeats only stepping and skipping. `/` is the search's own shortcut;
 * see `dashboard/dom/shortcut`.
 */
export class PlayerKeys extends ViewHook {
  private handler?: (event: KeyboardEvent) => void

  mounted(): void {
    const shortcuts = JSON.parse(this.el.dataset.shortcuts ?? '[]') as Shortcut[]
    const bindings: Record<string, (event: KeyboardEvent) => void> = {}

    for (const { id, keys } of shortcuts) {
      const action = ACTIONS[id]
      if (!action) continue
      for (const combination of keys)
        bindings[binding(combination)] = (event) => this.act(id, action, event)
    }

    this.handler = createKeybindingsHandler(bindings, { ignore: ignored })
    window.addEventListener('keydown', this.handler)
  }

  destroyed(): void {
    if (this.handler) window.removeEventListener('keydown', this.handler)
  }

  private act(id: string, action: Action, event: KeyboardEvent): void {
    if (event.repeat && !REPEATABLE.has(id)) return
    event.preventDefault()

    if ('click' in action) {
      const control = document.querySelector<HTMLElement>(action.click)
      if (control && !control.hasAttribute('disabled')) control.click()
    } else {
      this.pushEvent(action.push, action.payload ?? {}).catch(() => undefined)
    }
  }
}

// Where the player takes no keys at all.
const ignored = (event: KeyboardEvent): boolean => {
  if (event.defaultPrevented || event.isComposing || document.querySelector(MODAL)) return true

  const target = event.target instanceof Element ? event.target : null
  return Boolean(target?.closest(EDITABLE) || (event.key === ' ' && target?.closest(PRESSABLE)))
}
