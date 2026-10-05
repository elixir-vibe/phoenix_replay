import { afterEach, expect, test } from 'volt:test'

import { html } from '../test/hooks'
import { DETAILS_HEIGHT_KEY, DetailsResizer } from './details_resizer'

afterEach(() => {
  document.body.replaceChildren()
  localStorage.removeItem(DETAILS_HEIGHT_KEY)
})

const panel = (): { container: HTMLElement; divider: HTMLElement } => {
  const container = html(`
    <div id="details-panel" style="--details: 200px">
      <div data-container="details-panel" tabindex="0"></div>
      <section style="height: var(--details)"></section>
    </div>
  `)
  document.body.append(container)
  return { container, divider: container.firstElementChild as HTMLElement }
}

// LiveView keeps what the hook's js() sets; here it is set directly.
const mount = (divider: HTMLElement): DetailsResizer => {
  const hook = new DetailsResizer(null as never, divider)
  hook.js = () =>
    ({
      setAttribute: (el: HTMLElement, name: string, value: string) => el.setAttribute(name, value)
    }) as never
  hook.mounted()
  return hook
}

const pointer = (type: string, el: HTMLElement, y: number): void => {
  el.dispatchEvent(new PointerEvent(type, { clientY: y, pointerId: 1, bubbles: true }))
}

test('dragging the divider up makes the pane taller, and the height is kept', () => {
  const { container, divider } = panel()
  mount(divider)

  pointer('pointerdown', divider, 500)
  pointer('pointermove', divider, 420)
  expect(container.getAttribute('style')).toBe('--details: 280px')
  pointer('pointerup', divider, 420)
  expect(localStorage.getItem(DETAILS_HEIGHT_KEY)).toBe('280')

  // Never smaller than a few lines.
  pointer('pointerdown', divider, 400)
  pointer('pointermove', divider, 900)
  expect(container.getAttribute('style')).toBe('--details: 96px')
})

test('arrow keys move the divider, and a kept height applies on the next visit', () => {
  localStorage.setItem(DETAILS_HEIGHT_KEY, '240')
  const { container, divider } = panel()
  mount(divider)
  expect(container.getAttribute('style')).toBe('--details: 240px')

  divider.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }))
  expect(container.getAttribute('style')).toBe('--details: 256px')
  expect(divider.getAttribute('aria-valuenow')).toBe('256')
})
