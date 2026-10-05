import { afterEach, expect, test } from 'volt:test'

import type { PointerSettings } from './pointer'
import type { Batch } from './pointer_track'
import { replayRecorder } from './recorder'

let stop = (): void => {}

afterEach(() => {
  stop()
  document.body.replaceChildren()
})

const settings: PointerSettings = { sample: 40, scroll: 100, flush: 60_000, max_points: 500 }

// A LiveView's root element and a socket that collects the batches pushed to it.
const setup = (): Batch[] => {
  const main = document.createElement('div')
  main.dataset.phxMain = ''
  main.id = 'phx-GNuOmbTkq0ZBagSq'
  main.innerHTML =
    '<button id="save" style="position: fixed; left: 100px; top: 100px; width: 100px; height: 40px">Save</button>'
  document.body.append(main)

  const batches: Batch[] = []

  stop = replayRecorder({
    execJS: (el, encoded) => {
      expect(el).toBe(main)
      const [[command, { event, value }]] = JSON.parse(encoded) as [
        [string, { event: string; value: Batch }]
      ]
      expect(command).toBe('push')
      if (event !== 'phx_replay:pointer') return
      batches.push(value)
    }
  })

  return batches
}

const announce = (detail: Partial<PointerSettings> = {}): void => {
  window.dispatchEvent(
    new CustomEvent('phx:phx_replay:record', {
      detail: { pointer: { ...settings, ...detail }, state: null }
    })
  )
}

const pointer = (type: string, x: number, y: number, init: PointerEventInit = {}): void => {
  const target = document.elementFromPoint(x, y) ?? document.body
  target.dispatchEvent(
    new PointerEvent(type, {
      clientX: x,
      clientY: y,
      bubbles: true,
      pointerType: 'mouse',
      pointerId: 1,
      ...init
    })
  )
}

const wait = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms))

// Dispatches a touch event in which `changed` fingers, `[id, x, y]`, changed.
const touch = (type: string, changed: [number, number, number][]): void => {
  const target =
    document.elementFromPoint(changed[0]?.[1] ?? 0, changed[0]?.[2] ?? 0) ?? document.body
  const touches = changed.map(
    ([identifier, clientX, clientY]) => new Touch({ identifier, target, clientX, clientY })
  )
  target.dispatchEvent(new TouchEvent(type, { changedTouches: touches, touches, bubbles: true }))
}

const leave = (kind: string): void => {
  window.dispatchEvent(new CustomEvent('phx:page-loading-start', { detail: { kind } }))
}

test('records nothing until a LiveView asks', () => {
  const batches = setup()
  pointer('pointermove', 10, 10)
  leave('redirect')
  expect(batches).toEqual([])
})

test('samples moves at most every sample ms, keeping where the pointer came to rest', async () => {
  const batches = setup()
  announce()

  pointer('pointermove', 10, 10)
  pointer('pointermove', 11, 11)
  pointer('pointermove', 12, 12)
  await wait(80)
  leave('redirect')

  const [batch] = batches
  expect(batch?.m.length).toBe(8)
  expect(batch?.m.slice(1, 3)).toEqual([10, 10])
  expect(batch?.m.slice(5, 7)).toEqual([12, 12])
})

test("anchors presses to an element with a lasting id, not LiveView's own", () => {
  const batches = setup()
  announce()

  // The LiveView root's phx- id changes with each mount.
  pointer('pointerdown', 600, 600)
  leave('redirect')

  const [, , , , , , target] = batches[0]?.p[0] ?? []
  expect(target).toBe(null)
})

test('records presses on the nearest element with an id, and where within it', () => {
  const batches = setup()
  announce()

  pointer('pointerdown', 150, 110)
  pointer('pointerup', 150, 110)
  leave('redirect')

  const [down, up] = batches[0]?.p ?? []
  expect(down?.slice(1)).toEqual([0, 150, 110, 0, 0, 'save', 500, 250])
  expect(up?.slice(1, 7)).toEqual([1, 150, 110, 0, 0, null])
})

test('gives each finger its own slot, and sends a full batch early', () => {
  const batches = setup()
  // The scroll offset taken on starting counts too.
  announce({ max_points: 3 })

  // Safari's identifiers are addresses, not 0, 1, 2.
  touch('touchstart', [[1_947_211_840, 20, 20]])
  touch('touchstart', [[1_947_212_096, 40, 40]])

  expect(batches.length).toBe(1)
  const slots = batches[0]?.p.map(([, , , , slot, type]) => [slot, type])
  expect(slots).toEqual([
    [1, 1],
    [2, 1]
  ])
})

test('follows both fingers of a pinch, which the browser cancels as pointer events', async () => {
  const batches = setup()
  announce({ sample: 10 })

  touch('touchstart', [
    [5, 100, 100],
    [6, 200, 200]
  ])
  // The browser takes the gesture over: its pointer events stop here.
  pointer('pointercancel', 100, 100, { pointerType: 'touch', pointerId: 5 })
  pointer('pointercancel', 200, 200, { pointerType: 'touch', pointerId: 6 })

  for (const step of [10, 20, 30]) {
    touch('touchmove', [
      [5, 100 - step, 100 - step],
      [6, 200 + step, 200 + step]
    ])
    await wait(15)
  }

  touch('touchend', [
    [5, 70, 70],
    [6, 230, 230]
  ])
  leave('redirect')

  const [batch] = batches
  const moves = batch?.m ?? []
  const bySlot = (slot: number): number[][] => {
    const points: number[][] = []
    for (let i = 0; i < moves.length; i += 4)
      if (moves[i + 3] === slot) points.push([moves[i + 1] ?? 0, moves[i + 2] ?? 0])
    return points
  }

  // Each finger moved apart, to where it was lifted.
  expect(bySlot(1).at(-1)).toEqual([70, 70])
  expect(bySlot(2).at(-1)).toEqual([230, 230])

  // Only the touches' own down and up: no presses from the cancelled pointers.
  expect(batch?.p.map(([, kind, , , slot]) => [kind, slot])).toEqual([
    [0, 1],
    [0, 2],
    [1, 1],
    [1, 2]
  ])
})

test('keeps recording through a patch, and stops when leaving the LiveView', () => {
  const batches = setup()
  announce()

  leave('patch')
  pointer('pointerdown', 20, 20)
  leave('redirect')
  pointer('pointerdown', 30, 30)
  leave('redirect')

  expect(batches.length).toBe(1)
  expect(batches[0]?.p.length).toBe(1)
})
