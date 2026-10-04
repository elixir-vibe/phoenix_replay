import { afterEach, expect, test } from 'volt:test'

import { html, mountHook } from '../test/hooks'
import { FrameViewport } from './frame_viewport'

interface Frame {
  width: number
  height: number
  mode?: 'fit' | 'actual'
  maxHeight?: number
}

const section = ({ width, height, mode = 'fit', maxHeight = 600 }: Frame): HTMLElement =>
  html(`
    <section style="width: 600px" data-width="${width}" data-height="${height}" data-mode="${mode}" data-max-height="${maxHeight}">
      <style phx-update="ignore"></style>
      <style>#viewport-box, #viewport-frame { transition: none !important }</style>
      <span data-scale-label></span>
      <div id="viewport-box"><iframe id="viewport-frame" style="display: block; border: 0"></iframe></div>
    </section>
  `)

afterEach(() => {
  document.body.replaceChildren()
})

const measure = (
  el: HTMLElement
): { frame: CSSStyleDeclaration; box: CSSStyleDeclaration; label: string } => ({
  frame: getComputedStyle(el.querySelector('iframe') as HTMLIFrameElement),
  box: getComputedStyle(el.querySelector('#viewport-box') as HTMLElement),
  label: el.querySelector('[data-scale-label]')?.textContent ?? ''
})

test('fits a wide viewport to the width', () => {
  const el = section({ width: 1200, height: 800 })
  mountHook(FrameViewport, el)

  const { frame, box, label } = measure(el)
  expect(frame.width).toBe('1200px')
  expect(frame.transform).toBe('matrix(0.5, 0, 0, 0.5, 0, 0)')
  expect(box.height).toBe('400px')
  expect(label).toBe('1200 × 800 · 50%')
})

test('fits a tall viewport to the height, keeping its aspect ratio and centring it', () => {
  const el = section({ width: 390, height: 844, maxHeight: 422 })
  mountHook(FrameViewport, el)

  const { frame, box, label } = measure(el)
  expect(frame.transform).toBe('matrix(0.5, 0, 0, 0.5, 0, 0)')
  expect(box.height).toBe('422px')
  // 600 wide, 195 shown: centred.
  expect(frame.marginLeft).toBe('203px')
  expect(label).toBe('390 × 844 · 50%')
})

test('never scales up a viewport that fits', () => {
  const el = section({ width: 390, height: 500 })
  mountHook(FrameViewport, el)

  expect(measure(el).label).toBe('390 × 500 · 100%')
})

test('renders at 100% in a scrolling box in actual mode', () => {
  const el = section({ width: 390, height: 844, mode: 'actual', maxHeight: 422 })
  mountHook(FrameViewport, el)

  const { frame, box, label } = measure(el)
  expect(frame.transform).toBe('matrix(1, 0, 0, 1, 0, 0)')
  expect(box.height).toBe('422px')
  expect(box.overflowY).toBe('auto')
  expect(label).toBe('390 × 844 · 100%')
})

test('follows a new viewport and mode, and clears the sizes without one', () => {
  const el = section({ width: 390, height: 844, maxHeight: 422 })
  const { hook } = mountHook(FrameViewport, el)

  el.dataset.width = '844'
  el.dataset.height = '390'
  hook.updated?.()
  expect(measure(el).label).toBe('844 × 390 · 71%')

  el.dataset.mode = 'actual'
  hook.updated?.()
  expect(measure(el).label).toBe('844 × 390 · 100%')

  delete el.dataset.width
  delete el.dataset.height
  hook.updated?.()
  expect(el.querySelector('style')?.textContent).toBe('')
  expect(measure(el).label).toBe('')
})

test('keeps the element named by data-below free under the frame', () => {
  const height = (below?: string): number => {
    const el = section({ width: 390, height: 4000, maxHeight: 0 })
    if (below) el.dataset.below = below
    mountHook(FrameViewport, el)
    const value = parseFloat(measure(el).box.height)
    el.remove()
    return value
  }

  const alone = height()
  document.body.insertAdjacentHTML('beforeend', '<div id="controls" style="height: 300px"></div>')
  const controls = document.getElementById('controls') as HTMLElement
  const withControls = height('controls')
  controls.remove()

  // Scales are floored to whole percents, so the difference is about 300 px.
  expect(alone - withControls).toBeGreaterThan(260)
  expect(alone - withControls).toBeLessThan(340)
})
