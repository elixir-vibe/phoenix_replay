import { afterEach, expect, test } from 'volt:test'

import { ROOT_EVENT, replayRoot } from './root'

let stop = (): void => {}

afterEach(() => {
  stop()
  for (const name of ['data-theme', 'data-mode']) document.documentElement.removeAttribute(name)
  document.body.removeAttribute('data-page')
})

const push = (detail: object): void => {
  window.dispatchEvent(new CustomEvent(ROOT_EVENT, { detail }))
}

const layout = (html: string, body: string): string =>
  `<!DOCTYPE html><html ${html}><head></head><body ${body}></body></html>`

test("copies the root layout's <html> and <body> attributes, and drops those it no longer renders", () => {
  const { documentElement: root, body } = document
  stop = replayRoot(window)

  push({
    layout: layout('data-theme="dark"', 'data-page="tasks"'),
    attributes: { 'data-mode': 'compact' }
  })
  expect(root.getAttribute('data-theme')).toBe('dark')
  expect(root.getAttribute('data-mode')).toBe('compact')
  expect(body.getAttribute('data-page')).toBe('tasks')

  push({ layout: layout('data-theme="light"', ''), attributes: { 'data-mode': null } })
  expect(root.getAttribute('data-theme')).toBe('light')
  expect(root.hasAttribute('data-mode')).toBe(false)
  expect(body.hasAttribute('data-page')).toBe(false)
})
