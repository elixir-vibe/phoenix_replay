import { afterEach, expect, test } from 'volt:test'

import { html } from '../test/hooks'
import { matches, PlayerKeys, type Shortcut, shortcutFor } from './player_keys'

afterEach(() => document.body.replaceChildren())

const SHORTCUTS: Shortcut[] = [
  { id: 'toggle', keys: [['Space'], ['K']] },
  { id: 'next', keys: [['ArrowRight']] },
  { id: 'forward', keys: [['Shift', 'ArrowRight']] },
  { id: 'next_error', keys: [['E']] },
  { id: 'previous_error', keys: [['Shift', 'E']] },
  { id: 'pointer', keys: [['P']] },
  { id: 'help', keys: [['?']] }
]

const key = (init: KeyboardEventInit): KeyboardEvent =>
  new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init })

const mount = (): { pushed: [string, unknown][]; hook: PlayerKeys } => {
  const el = html(`<div data-shortcuts='${JSON.stringify(SHORTCUTS)}' hidden></div>`)
  document.body.append(el)
  const pushed: [string, unknown][] = []
  const hook = new PlayerKeys(null as never, el)
  hook.pushEvent = ((event: string, payload: unknown) => {
    pushed.push([event, payload])
    return Promise.resolve({})
  }) as never
  hook.mounted()
  return { pushed, hook }
}

test('letters and named keys need Shift as written; symbols come with any', () => {
  expect(matches(['K'], key({ key: 'k' }))).toBe(true)
  expect(matches(['K'], key({ key: 'K', shiftKey: true }))).toBe(false)
  expect(matches(['Shift', 'E'], key({ key: 'E', shiftKey: true }))).toBe(true)
  expect(matches(['ArrowRight'], key({ key: 'ArrowRight', shiftKey: true }))).toBe(false)
  expect(matches(['Space'], key({ key: ' ' }))).toBe(true)
  expect(matches(['?'], key({ key: '?', shiftKey: true }))).toBe(true)

  expect(shortcutFor(SHORTCUTS, key({ key: 'e' }))?.id).toBe('next_error')
  expect(shortcutFor(SHORTCUTS, key({ key: 'E', shiftKey: true }))?.id).toBe('previous_error')
  expect(shortcutFor(SHORTCUTS, key({ key: 'x' }))).toBeUndefined()
})

test('pushes the shortcut and keeps the page from scrolling', () => {
  const { pushed, hook } = mount()

  const space = key({ key: ' ' })
  document.body.dispatchEvent(space)
  expect(space.defaultPrevented).toBe(true)

  document.body.dispatchEvent(key({ key: 'ArrowRight', shiftKey: true }))
  document.body.dispatchEvent(key({ key: '?', shiftKey: true }))
  expect(pushed).toEqual([
    ['toggle', {}],
    ['skip', { by: 5_000 }],
    ['shortcuts', {}]
  ])

  hook.destroyed()
  document.body.dispatchEvent(key({ key: 'k' }))
  expect(pushed).toHaveLength(3)
})

test('leaves keys alone while typing, with modifiers, and already handled', () => {
  const { pushed } = mount()
  const input = html('<input type="search">')
  document.body.append(input)

  input.dispatchEvent(key({ key: 'k' }))
  document.body.dispatchEvent(key({ key: 'k', metaKey: true }))
  document.body.dispatchEvent(key({ key: 'k', ctrlKey: true }))
  document.body.dispatchEvent(key({ key: 'k', altKey: true }))

  const handled = key({ key: 'ArrowRight' })
  handled.preventDefault()
  document.body.dispatchEvent(handled)

  expect(pushed).toEqual([])
})

test('the space bar presses a focused control; held keys repeat only stepping', () => {
  const { pushed } = mount()
  const button = html('<button type="button">Other</button>')
  document.body.append(button)

  const space = key({ key: ' ' })
  button.dispatchEvent(space)
  expect(space.defaultPrevented).toBe(false)
  // K is not a key the button takes.
  button.dispatchEvent(key({ key: 'k' }))

  document.body.dispatchEvent(key({ key: 'k', repeat: true }))
  document.body.dispatchEvent(key({ key: 'ArrowRight', repeat: true }))

  expect(pushed).toEqual([
    ['toggle', {}],
    ['next', {}]
  ])
})

test('clicks a control the shortcut stands for, unless it is disabled', () => {
  mount()
  const control = html('<button id="replay-pointer-switch" type="button"></button>')
  document.body.append(control)
  let clicks = 0
  control.addEventListener('click', () => clicks++)

  document.body.dispatchEvent(key({ key: 'p' }))
  expect(clicks).toBe(1)

  control.setAttribute('disabled', '')
  document.body.dispatchEvent(key({ key: 'p' }))
  expect(clicks).toBe(1)
})
