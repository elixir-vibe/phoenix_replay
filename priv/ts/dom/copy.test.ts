import { afterEach, expect, test } from 'volt:test'

import { html } from '../test/hooks'
import { copyLinks } from './copy'

let stop = (): void => {}

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
  await Promise.resolve()

  expect(written).toEqual([new URL('/replay/abc?at=4', location.href).href])
  expect(button.dataset.copied).toBe('')
})

test('leaves the element unmarked when copying fails', async () => {
  stop = copyLinks(window, () => Promise.reject(new Error('denied')))
  const button = html('<button data-copy="/x">Copy</button>')
  document.body.append(button)

  button.click()
  await Promise.resolve()

  expect(button.dataset.copied).toBeUndefined()
})
