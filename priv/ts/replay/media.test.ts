import { afterEach, expect, test } from 'volt:test'

import { applyMedia } from './media'

afterEach(() => {
  document.body.replaceChildren()
})

// A page whose body is dark-blue in dark mode and light-yellow in light
// mode, whose text is red on a touch screen, and whose body has an outline
// only where it can hover.
const page = async (): Promise<Document> => {
  const frame = document.createElement('iframe')
  frame.srcdoc = `<style>
    @media (prefers-color-scheme: dark) { body { background: rgb(0, 0, 128) } }
    @media screen and (prefers-color-scheme: light) { body { background: rgb(255, 255, 224) } }
    @media (pointer: coarse) { body { color: rgb(255, 0, 0) } }
    @media (hover: hover) { body { outline: 1px solid } }
  </style>`
  const loaded = new Promise((resolve) => frame.addEventListener('load', resolve, { once: true }))
  document.body.append(frame)
  await loaded
  return frame.contentDocument as Document
}

const style = (doc: Document): CSSStyleDeclaration => getComputedStyle(doc.body)

test('makes the page show the recorded media, whatever the viewer has', async () => {
  const doc = await page()

  applyMedia(doc, { 'prefers-color-scheme': 'dark', pointer: 'coarse', hover: 'none' })
  expect(style(doc).backgroundColor).toBe('rgb(0, 0, 128)')
  expect(style(doc).color).toBe('rgb(255, 0, 0)')
  expect(style(doc).outlineStyle).toBe('none')

  applyMedia(doc, { 'prefers-color-scheme': 'light', pointer: 'fine', hover: 'hover' })
  expect(style(doc).backgroundColor).toBe('rgb(255, 255, 224)')
  expect(style(doc).color).not.toBe('rgb(255, 0, 0)')
  expect(style(doc).outlineStyle).toBe('solid')
})

test('puts the rules back without recorded media', async () => {
  const doc = await page()
  const own = style(doc).backgroundColor

  applyMedia(doc, { 'prefers-color-scheme': 'dark' })
  applyMedia(doc, {})
  expect(style(doc).backgroundColor).toBe(own)
})
