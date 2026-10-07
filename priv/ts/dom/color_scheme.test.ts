import { afterEach, expect, test } from 'volt:test'

import { applyColorScheme } from './color_scheme'

afterEach(() => {
  document.body.replaceChildren()
})

// A page whose body is dark-blue in dark mode and light-yellow in light mode.
const page = async (): Promise<Document> => {
  const frame = document.createElement('iframe')
  frame.srcdoc = `<style>
    @media (prefers-color-scheme: dark) { body { background: rgb(0, 0, 128) } }
    @media screen and (prefers-color-scheme: light) { body { background: rgb(255, 255, 224) } }
  </style>`
  const loaded = new Promise((resolve) => frame.addEventListener('load', resolve, { once: true }))
  document.body.append(frame)
  await loaded
  return frame.contentDocument as Document
}

const background = (doc: Document): string => getComputedStyle(doc.body).backgroundColor

test('makes the page show the recorded scheme, whatever the viewer prefers', async () => {
  const doc = await page()

  applyColorScheme(doc, 'dark')
  expect(background(doc)).toBe('rgb(0, 0, 128)')

  applyColorScheme(doc, 'light')
  expect(background(doc)).toBe('rgb(255, 255, 224)')
})

test('puts the rules back without a recorded scheme', async () => {
  const doc = await page()
  const own = background(doc)

  applyColorScheme(doc, 'dark')
  applyColorScheme(doc, undefined)
  expect(background(doc)).toBe(own)
})
