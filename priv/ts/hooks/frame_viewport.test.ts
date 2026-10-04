import { afterEach, expect, test } from 'volt:test'

import { html, mountHook } from '../test/hooks'
import { FrameViewport } from './frame_viewport'

const section = (width?: number, height?: number): HTMLElement =>
  html(`
    <section style="width: 600px"${width ? ` data-width="${width}" data-height="${height}"` : ''}>
      <style phx-update="ignore"></style>
      <div id="viewport-box"><iframe id="viewport-frame" style="display: block; border: 0"></iframe></div>
    </section>
  `)

afterEach(() => {
  document.body.replaceChildren()
})

const size = (el: HTMLElement): { frame: CSSStyleDeclaration; box: CSSStyleDeclaration } => ({
  frame: getComputedStyle(el.querySelector('iframe') as HTMLIFrameElement),
  box: getComputedStyle(el.querySelector('#viewport-box') as HTMLElement)
})

test('scales a wider recorded viewport down to fit', () => {
  const el = section(1200, 800)
  mountHook(FrameViewport, el)

  const { frame, box } = size(el)
  expect(frame.width).toBe('1200px')
  expect(frame.transform).toBe('matrix(0.5, 0, 0, 0.5, 0, 0)')
  expect(box.height).toBe('400px')
})

test('keeps a narrower recorded viewport at its size', () => {
  const el = section(390, 844)
  mountHook(FrameViewport, el)

  const { frame, box } = size(el)
  expect(frame.width).toBe('390px')
  expect(frame.marginLeft).toBe('105px')
  expect(box.height).toBe('844px')
})

test('follows a new viewport, and clears the sizes without one', () => {
  const el = section(390, 844)
  const { hook } = mountHook(FrameViewport, el)

  el.dataset.width = '1200'
  el.dataset.height = '600'
  hook.updated?.()
  expect(size(el).box.height).toBe('300px')

  delete el.dataset.width
  delete el.dataset.height
  hook.updated?.()
  expect(el.querySelector('style')?.textContent).toBe('')
})
