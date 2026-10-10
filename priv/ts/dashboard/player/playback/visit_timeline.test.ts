import { afterEach, expect, test } from 'volt:test'

import { html, mountHook } from '../../../test/hooks'
import { VisitTimeline } from './visit_timeline'

const timeline = (at: number): HTMLElement =>
  html(`
    <div style="position: relative; width: 1000px; height: 20px"
         data-duration="10000" data-speed="1" data-at="${at}" data-until="${at}" data-playing="false">
      <span data-thumb style="position: absolute"></span>
    </div>
  `)

const thumb = (el: HTMLElement): string =>
  el.querySelector<HTMLElement>('[data-thumb]')?.style.left ?? ''

const pointer = (type: string, el: HTMLElement, ratio: number): void => {
  const { left, width, top } = el.getBoundingClientRect()
  el.dispatchEvent(
    new PointerEvent(type, {
      clientX: left + width * ratio,
      clientY: top,
      pointerId: 1,
      bubbles: true
    })
  )
}

afterEach(() => {
  document.body.replaceChildren()
})

test('places the playhead at the visit time', () => {
  const el = timeline(2500)
  mountHook(VisitTimeline, el)
  expect(thumb(el)).toBe('25%')
})

test('follows the pointer while held, and seeks once, where it is let go', () => {
  const el = timeline(0)
  const { pushed } = mountHook(VisitTimeline, el)

  pointer('pointerdown', el, 0.6)
  pointer('pointermove', el, 0.3)
  expect(thumb(el)).toBe('30%')
  expect(pushed).toEqual([])

  pointer('pointerup', el, 0.4)
  expect(pushed).toEqual([['visit_seek', { at: 4000 }]])
  expect(thumb(el)).toBe('40%')
})

test('moves a few seconds on the visit clock with the arrow keys', () => {
  const el = timeline(4000)
  const { pushed } = mountHook(VisitTimeline, el)

  el.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true }))
  el.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true }))

  expect(pushed).toEqual([
    ['visit_seek', { at: 9000 }],
    ['visit_seek', { at: 0 }]
  ])
})
