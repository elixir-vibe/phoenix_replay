import { afterEach, expect, test } from 'volt:test'

import { ROOT_EVENT, replayRoot } from './replay_root'

let stop = (): void => {}

afterEach(() => {
  stop()
  for (const name of ['data-theme', 'data-mode']) document.documentElement.removeAttribute(name)
})

const push = (attributes: Record<string, string | null>): void => {
  window.dispatchEvent(new CustomEvent(ROOT_EVENT, { detail: { attributes } }))
}

test("sets the page's root attributes, and removes those no longer given", () => {
  const root = document.documentElement
  stop = replayRoot(window)

  push({ 'data-theme': 'dark', 'data-mode': 'compact' })
  expect(root.getAttribute('data-theme')).toBe('dark')
  expect(root.getAttribute('data-mode')).toBe('compact')

  push({ 'data-theme': 'light', 'data-mode': null })
  expect(root.getAttribute('data-theme')).toBe('light')
  expect(root.hasAttribute('data-mode')).toBe(false)
})
