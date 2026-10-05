import { afterEach, expect, test } from 'volt:test'

import {
  RECORDING_ATTRIBUTE,
  replayRecorder,
  START_EVENT,
  type StartDetail,
  STOP_EVENT
} from './recorder'
import type { StateBatch, StateSettings } from './state'

let stop = (): void => {}

afterEach(() => {
  stop()
  document.body.replaceChildren()
})

const settings: StateSettings = {
  flush: 60_000,
  max_entries: 3,
  max_key: 8,
  max_entry_bytes: 40,
  max_bytes: 1_000
}

// A LiveView's root element and a socket that collects what is pushed to it.
const setup = (): { event: string; value: unknown }[] => {
  const main = document.createElement('div')
  main.dataset.phxMain = ''
  document.body.append(main)

  const pushed: { event: string; value: unknown }[] = []

  stop = replayRecorder({
    execJS: (_el, encoded) => {
      const [[, push]] = JSON.parse(encoded) as [[string, { event: string; value: unknown }]]
      pushed.push(push)
    }
  })

  return pushed
}

const record = (state: StateSettings | null = settings): void => {
  window.dispatchEvent(
    new CustomEvent('phx:phx_replay:record', { detail: { pointer: null, state } })
  )
}

const report = (key: unknown, changes: unknown): void => {
  window.dispatchEvent(new CustomEvent('phx_replay:state', { detail: { key, changes } }))
}

const loading = (kind: string): void => {
  window.dispatchEvent(new CustomEvent('phx:page-loading-start', { detail: { kind } }))
}

const leave = (): void => loading('redirect')

const states = (pushed: { event: string; value: unknown }[]): StateBatch[] =>
  pushed.filter(({ event }) => event === 'phx_replay:state').map(({ value }) => value as StateBatch)

test('sends nothing while no session is recorded', () => {
  const pushed = setup()

  report('search', { query: 'shoes' })
  leave()

  expect(pushed).toEqual([])
})

test('signals start and stop, so other code can report its state', () => {
  setup()
  const seen: string[] = []
  let detail: StartDetail | undefined

  const onStart = (event: Event): void => {
    seen.push('start')
    detail = (event as CustomEvent<StartDetail>).detail
  }
  const onStop = (): void => {
    seen.push('stop')
  }

  window.addEventListener(START_EVENT, onStart)
  window.addEventListener(STOP_EVENT, onStop)

  record()
  leave()
  // A session without client state still signals.
  record(null)

  window.removeEventListener(START_EVENT, onStart)
  window.removeEventListener(STOP_EVENT, onStop)

  expect(seen).toEqual(['start', 'stop', 'start'])
  expect(detail).toEqual({ state: null })
})

test('sends reported state in batches, copying it when reported', () => {
  const pushed = setup()
  record()

  const changes = { query: 'sh' }
  report('search', changes)
  changes.query = 'changed later'
  report('search', { page: 2 })
  leave()

  const [batch] = states(pushed)
  expect(batch?.e.map(([, key, change]) => [key, change])).toEqual([
    ['search', { query: 'sh' }],
    ['search', { page: 2 }]
  ])
  expect(batch?.span).toBeGreaterThanOrEqual(0)
})

test('drops reports that are not a key and a JSON object within the limits', () => {
  const pushed = setup()
  record()

  report('', { a: 1 })
  report(7, { a: 1 })
  report('a-long-key', { a: 1 })
  report('k', [1, 2])
  report('k', null)
  report('k', { text: 'x'.repeat(50) })
  const cycle: Record<string, unknown> = {}
  cycle.self = cycle
  report('k', cycle)
  report('k', { kept: true })
  leave()

  expect(states(pushed).flatMap(({ e }) => e.map(([, , change]) => change))).toEqual([
    { kept: true }
  ])
})

test('sends a full batch early, and stops listening after leaving', () => {
  const pushed = setup()
  record()

  for (const n of [1, 2, 3, 4]) report('k', { n })
  expect(states(pushed).length).toBe(1)

  leave()
  report('k', { n: 5 })
  expect(states(pushed).flatMap(({ e }) => e).length).toBe(4)
})

test('keeps recording through page loading that stays on the LiveView', () => {
  const pushed = setup()
  record()

  // A patch, and an event pushed with page_loading: true.
  loading('patch')
  loading('element')
  report('k', { n: 1 })
  leave()

  expect(states(pushed).flatMap(({ e }) => e).length).toBe(1)
})

test('stops when the LiveView rejoins or loses its connection', () => {
  for (const kind of ['initial', 'error', 'redirect']) {
    const pushed = setup()
    record()
    loading(kind)
    report('k', { n: 1 })
    stop()

    expect(states(pushed)).toEqual([])
  }
})

test('marks the page while recording, for code that loads later', () => {
  setup()
  const html = document.documentElement
  expect(html.hasAttribute(RECORDING_ATTRIBUTE)).toBe(false)

  record()
  const detail = JSON.parse(html.getAttribute(RECORDING_ATTRIBUTE) ?? 'null') as StartDetail
  expect(detail.state?.max_key).toBe(8)

  leave()
  expect(html.hasAttribute(RECORDING_ATTRIBUTE)).toBe(false)

  record(null)
  expect(html.getAttribute(RECORDING_ATTRIBUTE)).toBe('{"state":null}')
})
