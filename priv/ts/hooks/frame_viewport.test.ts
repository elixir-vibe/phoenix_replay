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
  expect(frame.transform).toMatch(/^matrix\(0\.5, 0, 0, 0\.5,/)
  expect(box.height).toBe('400px')
  expect(label).toBe('1200 × 800 · 50%')
})

test('fits a tall viewport to the height, keeping its aspect ratio and centring it', () => {
  const el = section({ width: 390, height: 844, maxHeight: 422 })
  mountHook(FrameViewport, el)

  const { frame, box, label } = measure(el)
  expect(frame.transform).toMatch(/^matrix\(0\.5, 0, 0, 0\.5,/)
  expect(box.height).toBe('422px')
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
  expect(frame.transform).toMatch(/^matrix\(1, 0, 0, 1,/)
  expect(box.height).toBe('422px')
  expect(box.overflowY).toBe('auto')
  expect(label).toBe('390 × 844 · 100%')
})

test('turns the new layout into place from where the device was when the recording turns', () => {
  const el = section({ width: 390, height: 844, maxHeight: 422 })
  const { hook } = mountHook(FrameViewport, el)

  el.dataset.width = '844'
  el.dataset.height = '390'
  hook.updated?.()

  // The page takes its new layout at once, and turns in from portrait.
  expect(measure(el).label).toBe('844 × 390 · 71%')
  const animations = (el.querySelector('iframe') as HTMLIFrameElement).getAnimations()
  expect(animations.length).toBe(1)
  const frames = ((animations[0] as Animation).effect as KeyframeEffect).getKeyframes()
  expect(frames[0]?.transform).toContain('rotate(90deg)')
  expect(frames.at(-1)?.transform).toContain('rotate(0deg)')
})

test('follows a new viewport and mode, and clears the sizes without one', () => {
  const el = section({ width: 390, height: 844, maxHeight: 422 })
  const { hook } = mountHook(FrameViewport, el)

  el.dataset.width = '390'
  el.dataset.height = '500'
  hook.updated?.()
  expect(measure(el).label).toBe('390 × 500 · 84%')

  el.dataset.mode = 'actual'
  hook.updated?.()
  expect(measure(el).label).toBe('390 × 500 · 100%')

  delete el.dataset.width
  delete el.dataset.height
  hook.updated?.()
  expect(el.querySelector('style')?.textContent).toBe('')
  expect(measure(el).label).toBe('')
})

test('scrolls the box back when it goes from 100% to fit', () => {
  const el = section({ width: 1200, height: 800 })
  const { hook } = mountHook(FrameViewport, el)
  const box = el.querySelector('#viewport-box') as HTMLElement

  el.dataset.mode = 'actual'
  hook.updated?.()
  box.scrollTo(300, 200)
  expect(box.scrollLeft).toBe(300)

  el.dataset.mode = 'fit'
  hook.updated?.()
  expect([box.scrollLeft, box.scrollTop]).toEqual([0, 0])
})

test('holds the scrolled view, then eases from it into the fitted frame', () => {
  const el = section({ width: 1200, height: 800 })
  const { hook } = mountHook(FrameViewport, el)
  const box = el.querySelector('#viewport-box') as HTMLElement
  const style = el.querySelector('style') as HTMLStyleElement

  el.dataset.mode = 'actual'
  hook.updated?.()
  box.scrollTo(300, 200)

  // Every stylesheet the hook writes, in order.
  const written: string[] = []
  const property = Object.getOwnPropertyDescriptor(Node.prototype, 'textContent')
  Object.defineProperty(style, 'textContent', {
    get: () => property?.get?.call(style),
    set: (text: string) => {
      written.push(text)
      property?.set?.call(style, text)
    }
  })

  el.dataset.mode = 'fit'
  hook.updated?.()

  const [held, fitted] = written
  expect(held).toContain('transform:translate(-300px,-200px) rotate(0deg) scale(1)')
  expect(held).toContain('transition:none')
  expect(fitted).toContain('rotate(0deg) scale(0.5)')
  expect(measure(el).frame.transform).toMatch(/^matrix\(0\.5, 0, 0, 0\.5,/)
})
