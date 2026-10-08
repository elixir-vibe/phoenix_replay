import { afterEach, expect, test } from 'volt:test'

import { THEME_KEY, themeToggle } from './theme'

let stop = (): void => {}

afterEach(() => {
  stop()
  document.body.replaceChildren()
  delete document.documentElement.dataset.theme
  localStorage.removeItem(THEME_KEY)
})

const toggle = (): void => {
  ;(document.querySelector('[data-theme-toggle] svg') as Element).dispatchEvent(
    new MouseEvent('click', { bubbles: true })
  )
}

test('switches from the system appearance to the other theme, and back', () => {
  document.body.innerHTML = '<button data-theme-toggle><svg></svg></button>'
  stop = themeToggle(window)
  const system = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  const other = system === 'dark' ? 'light' : 'dark'

  toggle()
  expect(document.documentElement.dataset.theme).toBe(other)
  expect(localStorage.getItem(THEME_KEY)).toBe(other)

  toggle()
  expect(document.documentElement.dataset.theme).toBe(system)
})
