import { afterEach, expect, test } from 'volt:test'

import { html } from '../../test/hooks'
import { confirmClicks } from './confirm'

let stop = (): void => {}

afterEach(() => {
  stop()
  document.body.replaceChildren()
})

const clicks = (el: HTMLElement): string[] => {
  const seen: string[] = []
  el.addEventListener('click', () => seen.push('clicked'))
  return seen
}

test('lets the click through when confirmed', () => {
  const asked: string[] = []
  stop = confirmClicks(window, (message) => (asked.push(message), true))
  const button = html('<button data-confirm="Delete this recording?">Delete</button>')
  document.body.append(button)
  const seen = clicks(button)

  button.click()

  expect(asked).toEqual(['Delete this recording?'])
  expect(seen).toEqual(['clicked'])
})

test('stops the click when declined, including clicks on nested elements', () => {
  stop = confirmClicks(window, () => false)
  const button = html('<button data-confirm="Delete?"><span>Delete</span></button>')
  document.body.append(button)
  const seen = clicks(button)

  button.querySelector('span')?.click()

  expect(seen).toEqual([])
})

test('ignores elements without data-confirm', () => {
  let asked = false
  stop = confirmClicks(window, () => ((asked = true), false))
  const button = html('<button>Play</button>')
  document.body.append(button)
  const seen = clicks(button)

  button.click()

  expect(asked).toBe(false)
  expect(seen).toEqual(['clicked'])
})
