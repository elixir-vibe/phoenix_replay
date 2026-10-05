import { afterEach, expect, test } from 'volt:test'

import { ViewportRecorder } from './viewport'

let recorder: ViewportRecorder | undefined

afterEach(() => {
  recorder?.stop()
  recorder = undefined
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

const wait = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms))

test('sends the viewport once it settles after a rotation, and only when it changed', async () => {
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

  await wait(260)
  expect(pushed).toEqual([['phx_replay:viewport', { width: 844, height: 390, dpr: 3 }]])

  // A resize that ends where it started sends nothing.
  target.rotate()
  target.rotate()
  await wait(260)
  expect(pushed.length).toBe(1)
})
