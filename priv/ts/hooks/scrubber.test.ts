import { afterEach, expect, test } from 'volt:test'

import { html, mountHook } from '../test/hooks'
import { Scrubber } from './scrubber'

const scrubber = (data: { at: number; playing?: boolean }): HTMLElement =>
  html(`
    <div style="position: relative; width: 1000px; height: 20px"
         data-offsets="[0,100,500,1000]" data-duration="1000" data-speed="1"
         data-at="${data.at}" data-next-at="${data.at}" data-playing="${data.playing ?? false}">
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

test('places the thumb at the current event', () => {
  const el = scrubber({ at: 500 })
  mountHook(Scrubber, el)
  expect(thumb(el)).toBe('50%')
})

const settle = (): Promise<void> => new Promise((resolve) => setTimeout(resolve, 0))

test('seeks to the time under the pointer, one seek at a time, while dragging', async () => {
  const el = scrubber({ at: 0 })
  const { pushed } = mountHook(Scrubber, el)

  pointer('pointerdown', el, 0.6)
  // Moves while the first seek is in flight: only the latest follows it.
  pointer('pointermove', el, 0.7)
  pointer('pointermove', el, 0.3)
  await settle()
  // In flight again, with a move waiting behind it when the pointer is let go.
  pointer('pointermove', el, 0.4)
  pointer('pointermove', el, 0.25)
  pointer('pointerup', el, 0.2)
  await settle()
  pointer('pointermove', el, 0.9)

  expect(pushed).toEqual([
    ['seek', { index: 2, at: 600 }],
    ['seek', { index: 1, at: 300 }],
    ['seek', { index: 1, at: 400 }],
    // The waiting move is dropped for where the thumb was let go.
    ['seek', { index: 1, at: 200 }]
  ])
  expect(thumb(el)).toBe('20%')
})

test('keeps the thumb under the pointer while the server answers a drag', () => {
  const el = scrubber({ at: 0 })
  const { hook } = mountHook(Scrubber, el)

  pointer('pointerdown', el, 0.3)
  // The server's patch renders the thumb at its own time, the first
  // render at 0 ms here, the event before a gap in the recording.
  el.dataset.at = '0'
  el.querySelector<HTMLElement>('[data-thumb]')!.style.left = '0%'
  hook.updated?.()
  expect(thumb(el)).toBe('30%')

  pointer('pointerup', el, 0.3)
  expect(thumb(el)).toBe('30%')
})

test('maps keys to player events', () => {
  const el = scrubber({ at: 0 })
  const { pushed } = mountHook(Scrubber, el)

  for (const key of ['ArrowRight', 'ArrowLeft', ' ', 'Enter']) {
    el.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true }))
  }

  expect(pushed).toEqual([
    ['next', {}],
    ['previous', {}],
    ['toggle', {}]
  ])
})
