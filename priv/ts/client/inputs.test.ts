import { afterEach, beforeEach, expect, test } from 'volt:test'

import { type Clock, fakeClock } from '../test/clock'
import type { InputValues } from '../shared/payloads'
import { INPUTS_KEY, InputRecorder, restoreInputs } from './inputs'
import { STATE_EVENT, type StateReport } from './state'

let recorder: InputRecorder | undefined
let stopListening = (): void => {}
let clock: Clock

// Debounces run when the test ticks the clock, not after real waits.
beforeEach(() => {
  clock = fakeClock()
})

afterEach(() => {
  clock.uninstall()
  recorder?.stop()
  recorder = undefined
  stopListening()
  document.body.replaceChildren()
})

// The input values reported, as `{selector: {name: value}}` each.
const listen = (): InputValues[] => {
  const reports: InputValues[] = []
  const onReport = (event: Event): void => {
    const { key, changes } = (event as CustomEvent<StateReport>).detail
    if (key === INPUTS_KEY) reports.push(changes as InputValues)
  }

  window.addEventListener(STATE_EVENT, onReport)
  stopListening = () => window.removeEventListener(STATE_EVENT, onReport)
  return reports
}

const page = (html: string): void => {
  document.body.innerHTML = html
}

const type = (selector: string, value: string): void => {
  const el = document.querySelector(selector) as HTMLInputElement
  el.value = value
  el.dispatchEvent(new Event('input', { bubbles: true }))
}

const click = (selector: string): void => {
  ;(document.querySelector(selector) as HTMLInputElement).click()
}

test('records what is typed once it pauses, not every key', () => {
  page('<input id="search" name="q">')
  const reports = listen()
  recorder = new InputRecorder(window, 30)

  for (const text of ['s', 'sh', 'sho', 'shoes']) type('#search', text)
  expect(reports).toEqual([])

  // The pause is 30 ms from the last key, not a moment less.
  clock.tick(29)
  expect(reports).toEqual([])
  clock.tick(1)
  expect(reports).toEqual([{ '#search': { q: 'shoes' } }])
})

test('never reads passwords, hidden inputs, card fields or ignored controls', async () => {
  page(`
    <form id="f">
      <input id="pass" type="password" name="password">
      <input id="shown" type="password" name="pw">
      <input id="secret" type="hidden" name="token" value="t">
      <input id="card" name="number" autocomplete="cc-number">
      <input id="code" name="code" autocomplete="one-time-code">
      <input id="new" name="choose" autocomplete="username new-password">
      <div data-phx-replay-ignore><input id="private" name="note"></div>
      <input name="loose">
      <input id="kept" name="kept">
    </form>
    <input name="formless">
  `)
  const reports = listen()
  recorder = new InputRecorder(window, 10)

  // A "show password" toggle makes the field text; it stays unread, also
  // when the field appeared after recording started.
  document.querySelector('#shown')?.setAttribute('type', 'text')
  document
    .querySelector('#f')
    ?.insertAdjacentHTML('beforeend', '<input id="late" type="password" name="pin">')
  document.querySelector('#late')?.setAttribute('type', 'text')
  await Promise.resolve()

  const unread = ['#pass', '#shown', '#late', '#card', '#code', '#new', '#private']
  for (const selector of [...unread, '[name="loose"]', '[name="formless"]']) type(selector, 'x')
  type('#kept', 'yes')
  clock.tick(40)

  // An input without an id is found by its form's id and its name; one
  // with neither is skipped.
  expect(reports).toEqual([{ '#f [name="loose"]': { loose: 'x' } }, { '#kept': { kept: 'yes' } }])
})

test('records checkboxes by value and a radio group by the chosen value', () => {
  page(`
    <form id="f">
      <input type="checkbox" name="tags" value="a">
      <input type="checkbox" name="tags" value="b">
      <input type="radio" name="size" value="s" checked>
      <input type="radio" name="size" value="m">
    </form>
  `)
  const reports = listen()
  recorder = new InputRecorder(window, 10)

  click('[value="b"]')
  click('[value="m"]')
  clock.tick(40)

  expect(reports).toEqual([
    { '#f [name="tags"][value="b"]': { tags: true } },
    { '#f [name="size"]': { size: 'm' } }
  ])
})

test('reports controls changed before it started, and what is pending when it stops', () => {
  page('<input id="early" name="early" value="rendered"><input id="late" name="late">')
  ;(document.querySelector('#early') as HTMLInputElement).value = 'typed'
  const reports = listen()

  recorder = new InputRecorder(window, 10_000)
  type('#late', 'pending')
  recorder.stop()
  recorder = undefined

  expect(reports).toEqual([{ '#early': { early: 'typed' } }, { '#late': { late: 'pending' } }])
})

test('puts values back, resets what is no longer recorded, and skips filtered ones', () => {
  page(`
    <form id="f">
      <input id="q" name="q" value="">
      <input id="note" name="note" value="rendered">
      <select id="pick" name="pick" multiple><option value="a">A</option><option value="b">B</option></select>
      <input type="radio" name="size" value="s"><input type="radio" name="size" value="m">
      <input id="token" name="token">
    </form>
  `)

  const restored = restoreInputs(document, {
    '#q': { q: 'shoes' },
    '#note': { note: 'typed' },
    '#pick': { pick: ['b'] },
    '#f [name="size"]': { size: 'm' },
    '#token': { token: '[FILTERED]' }
  })

  const value = (selector: string): string =>
    (document.querySelector(selector) as HTMLInputElement).value
  expect(value('#q')).toBe('shoes')
  expect(value('#note')).toBe('typed')
  expect((document.querySelector('#pick') as HTMLSelectElement).selectedOptions[0]?.value).toBe('b')
  expect((document.querySelector('[value="m"]') as HTMLInputElement).checked).toBe(true)
  expect(value('#token')).toBe('[FILTERED]')

  // Seeking back to before `#note` was typed into resets it; `#q`, whose
  // whole entry the sanitizer filtered, is left as it is.
  restoreInputs(document, { '#q': '[FILTERED]' as never }, restored)
  expect(value('#note')).toBe('rendered')
  expect(value('#q')).toBe('shoes')
})

test('adds nothing when a box is left after its typing was recorded', () => {
  page('<input id="search" name="q">')
  const reports = listen()
  recorder = new InputRecorder(window, 10)

  type('#search', 'shoes')
  clock.tick(30)
  ;(document.querySelector('#search') as HTMLInputElement).dispatchEvent(
    new Event('change', { bubbles: true })
  )
  clock.tick(30)

  expect(reports).toEqual([{ '#search': { q: 'shoes' } }])
})
