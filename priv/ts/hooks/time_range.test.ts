import { afterEach, expect, test } from 'volt:test'

import { html } from '../test/hooks'
import { fromLocalParts, TimeRange, toLocalParts, zoneLabel } from './time_range'

afterEach(() => document.body.replaceChildren())

test('reads and writes days and times in the viewer’s zone', () => {
  const iso = '2026-10-06T09:14:00.000Z'
  expect(fromLocalParts(toLocalParts(iso)!)).toBe(iso)
  expect(toLocalParts(undefined)).toBeNull()

  // A range's end runs to the end of its minute; days alone span whole days.
  const end = new Date(fromLocalParts({ date: '2026-10-06', time: '' }, true))
  expect([end.getHours(), end.getMinutes(), end.getSeconds()]).toEqual([23, 59, 59])
  expect(new Date(fromLocalParts({ date: '2026-10-06', time: '' })).getHours()).toBe(0)

  expect(zoneLabel(new Date(iso))).toMatch(/\(UTC([+−]\d+(:\d\d)?)?\)$/)
})

const mount = (from?: string, to?: string): { form: HTMLElement; pushed: unknown[] } => {
  const form = html(`
    <form ${from ? `data-from="${from}" data-to="${to}"` : ''}>
      <calendar-range></calendar-range>
      <input name="from_time" type="time" value="00:00">
      <input name="to_time" type="time" value="23:59">
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
  return { form, pushed }
}

test('fills the calendar and times from the range, and names the zone', () => {
  const from = '2026-10-03T09:30:00Z'
  const to = '2026-10-06T18:00:00Z'
  const { form } = mount(from, to)

  const calendar = form.querySelector('calendar-range') as HTMLElement & { value: string }
  expect(calendar.value).toBe(`${toLocalParts(from)!.date}/${toLocalParts(to)!.date}`)
  expect(form.querySelector<HTMLInputElement>('input[name="from_time"]')!.value).toBe(
    toLocalParts(from)!.time
  )
  expect(form.querySelector('[data-time-zone]')!.textContent).toContain('UTC')
})

test('sends the picked days and times in UTC, and nothing without days', () => {
  const { form, pushed } = mount()
  form.dispatchEvent(new Event('submit', { cancelable: true }))
  expect(pushed).toEqual([])

  const calendar = form.querySelector('calendar-range') as HTMLElement & { value: string }
  calendar.value = '2026-10-03/2026-10-06'
  form.querySelector<HTMLInputElement>('input[name="from_time"]')!.value = '09:30'
  form.dispatchEvent(new Event('submit', { cancelable: true }))

  expect(pushed).toEqual([
    [
      'time_range',
      {
        from: new Date('2026-10-03T09:30').toISOString(),
        to: new Date('2026-10-06T23:59:59.999').toISOString()
      }
    ]
  ])
})
