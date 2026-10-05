import { afterEach, expect, test } from 'volt:test'

import { html, mountHook } from '../test/hooks'
import { Pointer, position } from './pointer'
import { TIME_EVENT } from './scrubber'

afterEach(() => {
  document.body.replaceChildren()
})

const track = {
  moves: [
    [100, 10, 10, 0],
    [200, 30, 50, 0],
    [2_000, 90, 90, 0],
    [3_050, 60, 60, 1]
  ],
  presses: [
    [500, 0, 30, 50, 0, 0, null, 0, 0],
    [3_000, 0, 60, 60, 1, 1, null, 0, 0],
    [3_200, 1, 60, 60, 1, 1, null, 0, 0]
  ],
  scrolls: [[400, 0, 120]]
}

const overlay = (): HTMLElement => {
  const box = html(`
    <div>
      <iframe srcdoc="<body style='height: 3000px'></body>" style="width: 200px; height: 200px"></iframe>
      <div data-frame-overlay data-width="200" data-height="200" data-track='${JSON.stringify(track)}'></div>
    </div>
  `)
  document.body.append(box)
  return box.querySelector('[data-frame-overlay]') as HTMLElement
}

const at = (ms: number): void => {
  window.dispatchEvent(new CustomEvent(TIME_EVENT, { detail: ms }))
}

const cursor = (el: HTMLElement): string | null =>
  el.querySelector('[data-cursor]')?.getAttribute('transform') ?? null

test('interpolates the pointer between samples, but not across a pause', () => {
  const moves = track.moves.filter((move) => move[3] === 0) as [number, number, number, number][]

  expect(position(moves, 50)).toBe(null)
  expect(position(moves, 150)).toEqual([20, 30])
  // 1.8 s apart: the pointer rested where it was.
  expect(position(moves, 1_000)).toEqual([30, 50])
})

test('moves the cursor with the playback time', () => {
  const el = overlay()
  mountHook(Pointer, el)

  at(50)
  expect(cursor(el)).toBe(null)

  at(150)
  expect(cursor(el)).toBe('translate(20 30)')
  expect(el.querySelector('svg')?.getAttribute('viewBox')).toBe('0 0 200 200')
})

test('ripples where the pointer pressed, then fades', () => {
  const el = overlay()
  mountHook(Pointer, el)

  at(600)
  const ripple = el.querySelector('circle')
  expect(ripple?.getAttribute('cx')).toBe('30')
  expect(Number(ripple?.style.opacity)).toBeGreaterThan(0)

  at(1_500)
  expect(el.querySelector('circle')).toBe(null)
})

test('shows a fingertip while a touch is down, and hides the cursor', () => {
  const el = overlay()
  mountHook(Pointer, el)

  at(3_100)
  expect(el.querySelector('circle[data-slot="1"]')?.getAttribute('cx')).toBe('60')
  expect(cursor(el)).toBe(null)

  at(3_300)
  expect(el.querySelector('circle[data-slot="1"]')).toBe(null)
})

test('scrolls the replayed page as recorded', async () => {
  const el = overlay()
  const frame = el.parentElement?.querySelector('iframe') as HTMLIFrameElement
  await new Promise((resolve) => frame.addEventListener('load', resolve, { once: true }))
  mountHook(Pointer, el)

  at(500)
  expect(frame.contentWindow?.scrollY).toBe(120)
})
