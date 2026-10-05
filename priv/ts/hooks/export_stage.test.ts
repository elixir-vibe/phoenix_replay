import { afterEach, expect, test } from 'volt:test'

import { mountHook, html } from '../test/hooks'
import { ExportStage } from './export_stage'
import { TIME_EVENT } from './scrubber'

afterEach(() => {
  document.body.replaceChildren()
  delete window.phoenixReplayStage
})

const stage = async (): Promise<{
  el: HTMLElement
  frame: HTMLIFrameElement
  pushed: [string, unknown][]
}> => {
  const el = html(`
    <div style="position: fixed; inset: 0; width: 800px; height: 600px">
      <div style="position: absolute">
        <iframe srcdoc="<body></body>"></iframe>
        <div data-frame-overlay></div>
      </div>
    </div>
  `)
  const frame = el.querySelector('iframe') as HTMLIFrameElement
  const loaded = new Promise((resolve) => frame.addEventListener('load', resolve, { once: true }))
  const { pushed, receive } = mountHook(ExportStage, el)
  await loaded
  // The stage announces the frame once its LiveView connected.
  receive('phx_replay:frame_ready')
  await window.phoenixReplayStage?.ready()
  return { el, frame, pushed }
}

const frames = async (count: number): Promise<void> => {
  for (let i = 0; i < count; i++) await new Promise((resolve) => requestAnimationFrame(resolve))
}

const shown = (frame: HTMLIFrameElement, index: number): void => {
  frame.contentWindow?.dispatchEvent(new CustomEvent('phx:phx_replay:shown', { detail: { index } }))
}

test('shows a moment once the frame has rendered its event', async () => {
  const { el, frame, pushed } = await stage()
  const times: number[] = []
  window.addEventListener(TIME_EVENT, (event) => times.push((event as CustomEvent<number>).detail))

  let done = false
  const showing = window.phoenixReplayStage
    ?.show({ index: 3, at: 1_500, width: 400, height: 300 })
    .then(() => {
      done = true
    })

  // Not before the frame shows event 3: given the frames show waits for
  // after a render, it would have resolved by now.
  await frames(3)
  expect(done).toBe(false)
  shown(frame, 2)
  await frames(3)
  expect(done).toBe(false)

  shown(frame, 3)
  await showing
  expect(times).toEqual([1_500])

  // The device is sized to the viewport and centred on the stage.
  const device = el.firstElementChild as HTMLElement
  expect([device.style.width, device.style.height]).toEqual(['400px', '300px'])
  expect([device.style.left, device.style.top]).toEqual(['200px', '150px'])
  const overlay = el.querySelector<HTMLElement>('[data-frame-overlay]')
  expect([overlay?.dataset.width, overlay?.dataset.height]).toEqual(['400', '300'])

  // The stage was asked to seek, once.
  expect(pushed).toEqual([['seek', { index: 3 }]])

  // The same event again needs no seek and no new render.
  await window.phoenixReplayStage?.show({ index: 3, at: 1_600, width: 400, height: 300 })
  expect(times).toEqual([1_500, 1_600])
  expect(pushed).toHaveLength(1)
})
