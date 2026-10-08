import { afterEach, expect, test } from 'volt:test'

import { html } from '../../test/hooks'
import { searchShortcut } from './shortcut'

let stop = (): void => {}

afterEach(() => {
  stop()
  document.body.replaceChildren()
})

const press = (key: string, init: KeyboardEventInit = {}): KeyboardEvent => {
  // With the physical key a browser reports, as tinykeys needs one.
  const event = new KeyboardEvent('keydown', {
    key,
    code: 'Slash',
    bubbles: true,
    cancelable: true,
    ...init
  })
  ;(document.activeElement ?? document.body).dispatchEvent(event)
  return event
}

test('focuses the search field on /', () => {
  stop = searchShortcut(window)
  const field = html('<input type="search" data-shortcut="/">')
  document.body.append(field)

  const event = press('/')

  expect(document.activeElement).toBe(field)
  expect(event.defaultPrevented).toBe(true)
})

test('leaves / alone while typing elsewhere or with a modifier', () => {
  stop = searchShortcut(window)
  const field = html('<input type="search" data-shortcut="/">')
  const other = html('<input type="text">')
  document.body.append(field, other)

  other.focus()
  expect(press('/').defaultPrevented).toBe(false)
  expect(document.activeElement).toBe(other)

  other.blur()
  press('/', { metaKey: true })
  expect(document.activeElement).not.toBe(field)
})
