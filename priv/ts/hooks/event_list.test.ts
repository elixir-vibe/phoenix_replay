import { afterEach, expect, test } from 'volt:test'

import { html, mountHook } from '../test/hooks'
import { EventList } from './event_list'

const list = (current: number): HTMLElement =>
  html(`
    <ol style="position: relative; height: 100px; overflow-y: auto; margin: 0; padding: 0">
      ${Array.from(
        { length: 20 },
        (_, i) => `<li style="height: 20px"${i === current ? ' aria-current="step"' : ''}>${i}</li>`
      ).join('')}
    </ol>
  `)

afterEach(() => {
  document.body.replaceChildren()
})

test('scrolls the list, not the page, to the current event', () => {
  document.body.style.height = '5000px'
  const el = list(15)
  mountHook(EventList, el)

  expect(el.scrollTop).toBe(220)
  expect(window.scrollY).toBe(0)
})

test('scrolls back up when the current event is above the viewport', () => {
  const el = list(15)
  const { hook } = mountHook(EventList, el)

  el.querySelector('[aria-current]')?.removeAttribute('aria-current')
  el.children[2]?.setAttribute('aria-current', 'step')
  hook.updated?.()

  expect(el.scrollTop).toBe(40)
})
