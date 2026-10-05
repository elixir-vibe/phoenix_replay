import { afterEach, expect, test } from 'volt:test'

import { INPUTS_KEY, InputRecorder, type InputValues, restoreInputs } from './inputs'
import { STATE_EVENT, type StateReport } from './state'

let recorder: InputRecorder | undefined
let stopListening = (): void => {}

afterEach(() => {
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

const wait = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms))

test('records what is typed once it pauses, not every key', async () => {
  page('<input id="search" name="q">')
  const reports = listen()
  recorder = new InputRecorder(window, 30)

  for (const text of ['s', 'sh', 'sho', 'shoes']) type('#search', text)
  expect(reports).toEqual([])

  await wait(60)
  expect(reports).toEqual([{ '#search': { q: 'shoes' } }])
})

test('never reads passwords, hidden inputs, card fields or ignored controls', async () => {
  page(`
    <form id="f">
      <input id="pass" type="password" name="password">
      <input id="secret" type="hidden" name="token" value="t">
      <input id="card" name="number" autocomplete="cc-number">
      <div data-phx-replay-ignore><input id="private" name="note"></div>
      <input name="loose">
      <input id="kept" name="kept">
    </form>
    <input name="formless">
  `)
  const reports = listen()
  recorder = new InputRecorder(window, 10)

  for (const selector of ['#pass', '#card', '#private', '[name="loose"]', '[name="formless"]'])
    type(selector, 'x')
  type('#kept', 'yes')
  await wait(40)

  // An input without an id is found by its form's id and its name; one
  // with neither is skipped.
  expect(reports).toEqual([{ '#f [name="loose"]': { loose: 'x' } }, { '#kept': { kept: 'yes' } }])
})

test('records checkboxes by value and a radio group by the chosen value', async () => {
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
  await wait(40)

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
