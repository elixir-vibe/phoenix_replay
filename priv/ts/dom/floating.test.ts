import { afterEach, expect, test } from 'volt:test'

import { html } from '../test/hooks'
import { Floating, floatingTooltips, place } from './floating'

afterEach(() => document.body.replaceChildren())

const settle = (): Promise<void> => new Promise((resolve) => setTimeout(resolve, 20))

test('places an element by its anchor, on the other side when there is no room', async () => {
  const anchor = html(
    '<button style="position: fixed; top: 200px; left: 100px; width: 40px; height: 20px"></button>'
  )
  const floating = html('<div style="position: fixed; width: 80px; height: 30px"></div>')
  document.body.append(anchor, floating)

  expect(await place(anchor, floating, 'bottom-start')).toEqual({ x: 100, y: 226 })
  expect(await place(anchor, floating, 'top')).toEqual({ x: 80, y: 164 })

  // Near the top of the window, a tooltip above flips below.
  anchor.style.top = '0px'
  expect((await place(anchor, floating, 'top')).y).toBe(26)
})

test('shows a tooltip by its control as the pointer reaches it', async () => {
  floatingTooltips(window)
  const control = html(`
    <span data-tip style="position: fixed; top: 300px; left: 300px">
      <button style="width: 40px; height: 20px">Play</button>
      <span data-tip-content data-placement="bottom" style="position: fixed; width: 60px; height: 20px"></span>
    </span>
  `)
  document.body.append(control)

  control.querySelector('button')!.dispatchEvent(new PointerEvent('pointerover', { bubbles: true }))
  await settle()

  const tip = control.querySelector<HTMLElement>('[data-tip-content]')!
  expect(tip.style.top).toBe('326px')
})

test('keeps a menu by the element its data-anchor names', async () => {
  // Sized by a stylesheet, as classes size it, since the hook writes its style.
  const sheet = html('<style>#menu { position: fixed; width: 120px; height: 50px }</style>')
  const anchor = html(
    '<button id="menu-button" style="position: fixed; top: 100px; left: 150px; width: 40px; height: 20px"></button>'
  )
  const menu = html('<div id="menu" data-anchor="menu-button" data-placement="bottom-end"></div>')
  document.body.append(sheet, anchor, menu)

  const hook = new Floating(null as never, menu)
  hook.js = () =>
    ({
      setAttribute: (el: HTMLElement, name: string, value: string) => el.setAttribute(name, value)
    }) as never
  hook.mounted()
  await settle()

  expect(menu.getAttribute('style')).toBe('left: 70px; top: 126px')
  hook.destroyed()
})
