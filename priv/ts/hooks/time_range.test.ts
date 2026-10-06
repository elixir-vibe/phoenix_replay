import { afterEach, expect, test } from 'volt:test'

import { html } from '../test/hooks'
import { fromLocalInput, TimeRange, toLocalInput, zoneLabel } from './time_range'

afterEach(() => document.body.replaceChildren())

test('reads and writes datetime-local values in the viewer’s zone', () => {
  const iso = '2026-10-06T09:14:00.000Z'
  expect(fromLocalInput(toLocalInput(iso))).toBe(iso)
  expect(toLocalInput(undefined)).toBe('')
  expect(fromLocalInput('')).toBe('')
  expect(zoneLabel(new Date(iso))).toMatch(/\(UTC([+−]\d+(:\d\d)?)?\)$/)
})

test('fills the range, names the zone and sends the range in UTC', () => {
  const form = html(`
    <form data-from="2026-10-06T09:00:00Z">
      <input name="from" type="datetime-local"><input name="to" type="datetime-local">
      <span data-time-zone></span>
    </form>
  `)
  document.body.append(form)
  const pushed: unknown[] = []
  const hook = new TimeRange(null as never, form)
  hook.pushEvent = ((event: string, payload: unknown) => {
    pushed.push([event, payload])
    return Promise.resolve({})
  }) as never
  hook.mounted()

  const from = form.querySelector<HTMLInputElement>('input[name="from"]')!
  expect(from.value).toBe(toLocalInput('2026-10-06T09:00:00Z'))
  expect(form.querySelector('[data-time-zone]')!.textContent).toContain('UTC')

  form.dispatchEvent(new Event('submit', { cancelable: true }))
  expect(pushed).toEqual([['time_range', { from: '2026-10-06T09:00:00.000Z', to: '' }]])
})
