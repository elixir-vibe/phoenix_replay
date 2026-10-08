import { afterEach, expect, test } from 'volt:test'

import { html } from '../../test/hooks'
import { LocalTime, localText, localTitle } from './local_time'

afterEach(() => document.body.replaceChildren())

const mount = (format: string): HTMLElement => {
  const el = html(
    `<time datetime="2026-10-06T09:14:05.000Z" data-format="${format}" title="2026-10-06 09:14:05 UTC">12 s ago</time>`
  )
  document.body.append(el)
  new LocalTime(null as never, el).mounted()
  return el
}

const time = new Date('2026-10-06T09:14:05.000Z')

test('shows the time in the viewer’s zone, with it and UTC in the tooltip', () => {
  const el = mount('datetime')
  expect(el.textContent).toBe(localText(time, 'datetime'))
  expect(el.title).toBe(localTitle(time))
  expect(el.title).toContain('UTC')
})

test('keeps its own text for a title, and shows a date for a date', () => {
  expect(mount('title').textContent).toBe('12 s ago')
  expect(mount('date').textContent).toBe(
    new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(time)
  )
})
