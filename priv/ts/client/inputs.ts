/**
 * Records what is typed and chosen in form controls, with no app code, and
 * puts it back in the replay.
 *
 * Each control is identified by a selector: `#id` when it has an id,
 * otherwise its form's id and its own name, plus its value for a
 * checkbox, as checkboxes often share a name. A radio group without ids is
 * one control whose value is the chosen radio's. Controls with neither an
 * id nor a form id and name are skipped. Its value is reported under its name, so the server's
 * sanitizer filters names such as `token` as it does for event params:
 *
 *     replayState("phx_replay:inputs", { "#search": { query: "shoes" } })
 *
 * Never read at all: passwords, including one a "show password" toggle
 * turned into text, hidden and file inputs, buttons, fields whose
 * `autocomplete` names a card (`cc-…`), a password or a one-time code,
 * and anything inside an element with a `data-phx-replay-ignore`
 * attribute.
 */

import { replayState } from './state'
import type { InputValue, InputValues } from '../shared/payloads'

/** The state key form control values are reported under. */
export const INPUTS_KEY = 'phx_replay:inputs'

/** Excludes an element and everything inside it from input capture. */
export const IGNORE_ATTRIBUTE = 'data-phx-replay-ignore'

type Control = HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement

const SKIPPED_TYPES = new Set(['password', 'hidden', 'file', 'submit', 'button', 'reset', 'image'])
const SECRET_AUTOCOMPLETE = new Set(['current-password', 'new-password', 'one-time-code'])

// Inputs that were passwords: a "show password" toggle makes them text.
const passwords = new WeakSet<Element>()

const isControl = (el: unknown): el is Control =>
  el instanceof HTMLInputElement ||
  el instanceof HTMLTextAreaElement ||
  el instanceof HTMLSelectElement

/** Whether a control may be read at all. */
export const capturable = (el: Control): boolean => {
  if (el instanceof HTMLInputElement && el.type === 'password') passwords.add(el)

  return (
    !passwords.has(el) &&
    !(el instanceof HTMLInputElement && SKIPPED_TYPES.has(el.type)) &&
    !secretAutocomplete(el) &&
    el.closest(`[${IGNORE_ATTRIBUTE}]`) === null
  )
}

const secretAutocomplete = (el: Control): boolean =>
  (el.getAttribute('autocomplete') ?? '')
    .split(/\s+/)
    .some((token) => token.startsWith('cc-') || SECRET_AUTOCOMPLETE.has(token))

const isCheckable = (el: Control): el is HTMLInputElement =>
  el instanceof HTMLInputElement && (el.type === 'checkbox' || el.type === 'radio')

// A radio group without ids is recorded as one control: its chosen value.
const isGroupedRadio = (el: Control): el is HTMLInputElement =>
  el instanceof HTMLInputElement && el.type === 'radio' && !el.id

/** The selector a control is recorded and restored by, or `null`. */
export const identify = (el: Control): string | null => {
  if (el.id) return `#${CSS.escape(el.id)}`

  const form = el.form
  if (!form?.id || !el.name) return null

  const named = `#${CSS.escape(form.id)} [name="${CSS.escape(el.name)}"]`
  return el instanceof HTMLInputElement && el.type === 'checkbox'
    ? `${named}[value="${CSS.escape(el.value)}"]`
    : named
}

const read = (el: Control): InputValue => {
  if (el instanceof HTMLSelectElement && el.multiple)
    return Array.from(el.selectedOptions, (option) => option.value)
  if (isGroupedRadio(el))
    return el.form?.querySelector<HTMLInputElement>(`${identify(el)}:checked`)?.value ?? ''
  if (isCheckable(el)) return el.checked
  return el.value
}

// Whether the user changed a control from what the page rendered.
const changed = (el: Control): boolean => {
  if (el instanceof HTMLSelectElement)
    return Array.from(el.options).some((option) => option.selected !== option.defaultSelected)
  if (isCheckable(el)) return el.checked !== el.defaultChecked
  return el.value !== el.defaultValue
}

const field = (el: Control): string => el.name || el.id || 'value'

/** Records form controls while started; see `replayRecorder`. */
export class InputRecorder {
  private readonly pending = new Map<string, [Control, ReturnType<typeof setTimeout>]>()
  // What was last reported for each control, so leaving a box, which fires
  // `change` after the typing was reported, adds no second entry.
  private readonly reported = new Map<string, string>()
  private readonly onInput = (event: Event): void => this.changed(event.target)
  // Remembers a password whose type changes before anything is typed in it.
  private readonly typeChanges = new MutationObserver((mutations) => {
    for (const { target, oldValue } of mutations)
      if (oldValue === 'password') passwords.add(target as Element)
  })

  /** Reports the controls the user already changed, then each change after a pause. */
  constructor(
    private readonly target: Window,
    private readonly debounce: number
  ) {
    const document = target.document

    for (const el of Array.from(document.querySelectorAll('input, textarea, select'))) {
      if (isControl(el) && capturable(el) && changed(el)) this.report(el)
    }

    this.typeChanges.observe(document, {
      attributeFilter: ['type'],
      attributeOldValue: true,
      subtree: true
    })
    document.addEventListener('input', this.onInput, { capture: true, passive: true })
    document.addEventListener('change', this.onInput, { capture: true, passive: true })
  }

  /** Reports what is still pending, and stops. */
  stop(): void {
    for (const [el, timer] of this.pending.values()) {
      clearTimeout(timer)
      this.report(el)
    }

    this.pending.clear()
    this.typeChanges.disconnect()
    this.target.document.removeEventListener('input', this.onInput, { capture: true })
    this.target.document.removeEventListener('change', this.onInput, { capture: true })
  }

  // A typed sentence is one report, not one per key: each control waits
  // for `debounce` ms without changes.
  private changed(el: EventTarget | null): void {
    if (!isControl(el) || !capturable(el)) return

    const selector = identify(el)
    if (!selector) return

    clearTimeout(this.pending.get(selector)?.[1])

    const timer = setTimeout(() => {
      this.pending.delete(selector)
      this.report(el)
    }, this.debounce)

    this.pending.set(selector, [el, timer])
  }

  private report(el: Control): void {
    const selector = identify(el)
    if (!selector) return

    const value = read(el)
    const encoded = JSON.stringify(value)
    if (this.reported.get(selector) === encoded) return

    this.reported.set(selector, encoded)
    replayState(INPUTS_KEY, { [selector]: { [field(el)]: value } }, this.target)
  }
}

/**
 * Puts recorded values back into the controls of `document`, and returns
 * the selectors it restored. Controls restored before but not in `values`
 * now are reset to what the page rendered.
 */
export const restoreInputs = (
  document: Document,
  values: InputValues,
  previously: Iterable<string> = []
): Set<string> => {
  const restored = new Set<string>()

  for (const selector of previously) {
    if (!(selector in values)) for (const el of controls(document, selector)) reset(el)
  }

  for (const [selector, fields] of Object.entries(values)) {
    // A sanitized entry is a string such as "[FILTERED]", not a value.
    if (typeof fields !== 'object' || fields === null) continue

    for (const el of controls(document, selector)) write(el, Object.values(fields)[0])
    restored.add(selector)
  }

  return restored
}

const controls = (document: Document, selector: string): Control[] => {
  try {
    return Array.from(document.querySelectorAll(selector)).filter(isControl)
  } catch {
    return []
  }
}

const write = (el: Control, value: InputValue | undefined): void => {
  if (value === undefined) return

  if (el instanceof HTMLSelectElement) {
    const chosen = new Set(Array.isArray(value) ? value : [String(value)])
    for (const option of Array.from(el.options)) option.selected = chosen.has(option.value)
  } else if (isGroupedRadio(el)) {
    el.checked = el.value === value
  } else if (isCheckable(el)) {
    el.checked = value === true
  } else {
    el.value = String(value)
  }
}

const reset = (el: Control): void => {
  if (el instanceof HTMLSelectElement) {
    for (const option of Array.from(el.options)) option.selected = option.defaultSelected
  } else if (isCheckable(el)) {
    el.checked = el.defaultChecked
  } else {
    el.value = el.defaultValue
  }
}
