import { afterEach, expect, test } from 'volt:test'

import { type PointerSettings, replayPointer } from './pointer'

interface Batch {
  span: number
  m: number[]
  p: unknown[][]
  s: number[]
}

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
  main.innerHTML =
    '<button id="save" style="position: fixed; left: 100px; top: 100px; width: 100px; height: 40px">Save</button>'
  document.body.append(main)

  const batches: Batch[] = []

  stop = replayPointer({
    execJS: (el, encoded) => {
      expect(el).toBe(main)
      const [[command, { event, value }]] = JSON.parse(encoded) as [
        [string, { event: string; value: Batch }]
      ]
      expect(command).toBe('push')
      expect(event).toBe('phx_replay:pointer')
      batches.push(value)
    }
  })

  return batches
}

const announce = (detail: Partial<PointerSettings> = {}): void => {
  window.dispatchEvent(
    new CustomEvent('phx:phx_replay:pointer', { detail: { ...settings, ...detail } })
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

  pointer('pointerdown', 20, 20, { pointerType: 'touch', pointerId: 7 })
  pointer('pointerdown', 40, 40, { pointerType: 'touch', pointerId: 9 })

  expect(batches.length).toBe(1)
  const slots = batches[0]?.p.map((press) => press[4])
  expect(slots).toEqual([1, 2])
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
