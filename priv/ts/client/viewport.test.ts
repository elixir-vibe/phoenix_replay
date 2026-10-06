import { afterEach, expect, test } from 'volt:test'

import { type Clock, fakeClock } from '../test/clock'
import { ViewportRecorder } from './viewport'

let recorder: ViewportRecorder | undefined
let clock: Clock | undefined

afterEach(() => {
  recorder?.stop()
  recorder = undefined
  clock?.uninstall()
  clock = undefined
})

// A window whose size the test sets, as a rotation would.
class FakeWindow extends EventTarget {
  innerWidth = 390
  innerHeight = 844
  devicePixelRatio = 3

  rotate(): void {
    ;[this.innerWidth, this.innerHeight] = [this.innerHeight, this.innerWidth]
    this.dispatchEvent(new Event('resize'))
  }
}

test('sends the viewport once it settles after a rotation, and only when it changed', () => {
  clock = fakeClock()
  const target = new FakeWindow()
  const pushed: [string, unknown][] = []
  recorder = new ViewportRecorder(
    (event, value) => pushed.push([event, value]),
    target as unknown as Window
  )

  // A rotation fires several resizes; one viewport is sent when they stop.
  target.rotate()
  target.dispatchEvent(new Event('resize'))
  expect(pushed).toEqual([])

  // Quiet for 200 ms: not a moment before.
  clock.tick(199)
  expect(pushed).toEqual([])
  clock.tick(1)
  expect(pushed).toEqual([['phx_replay:viewport', { width: 844, height: 390, dpr: 3 }]])

  // A resize that ends where it started sends nothing.
  target.rotate()
  target.rotate()
  clock.tick(200)
  expect(pushed.length).toBe(1)
})
