import { afterEach, expect, test } from 'volt:test'

import { html } from '../test/hooks'
import { copyLinks } from './copy'

let stop = (): void => {}

// Lets the copy's promise chain settle.
const settle = (): Promise<void> => new Promise((resolve) => setTimeout(resolve, 0))

afterEach(() => {
  stop()
  document.body.replaceChildren()
})

test('copies the absolute link and marks the element', async () => {
  const written: string[] = []
  stop = copyLinks(window, (text) => (written.push(text), Promise.resolve()))
  const button = html('<button data-copy="/replay/abc?at=4"><span>Copy</span></button>')
  document.body.append(button)

  ;(button.firstElementChild as HTMLElement).click()
  await settle()

  expect(written).toEqual([new URL('/replay/abc?at=4', location.href).href])
  expect(button.dataset.copied).toBe('')
})

test('leaves the element unmarked when copying fails', async () => {
  stop = copyLinks(window, () => Promise.reject(new Error('denied')))
  const button = html('<button data-copy="/x">Copy</button>')
  document.body.append(button)

  button.click()
  await settle()

  expect(button.dataset.copied).toBeUndefined()
})

test('does nothing when the clipboard is unavailable, as on plain HTTP', async () => {
  stop = copyLinks(window, () => {
    throw new TypeError("Cannot read properties of undefined (reading 'writeText')")
  })
  const button = html('<button data-copy="/x">Copy</button>')
  document.body.append(button)
  // A throw inside a click listener reaches window.onerror, not the test.
  const errors: unknown[] = []
  const onError = (event: ErrorEvent): void => {
    errors.push(event.error)
    event.preventDefault()
  }
  window.addEventListener('error', onError)

  button.click()
  await settle()
  window.removeEventListener('error', onError)

  expect(errors).toEqual([])
  expect(button.dataset.copied).toBeUndefined()
})
