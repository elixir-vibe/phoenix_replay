import { afterEach, expect, test } from 'volt:test'

import { replayMetadata, replayParams, tabId } from './phoenix_replay'

afterEach(() => {
  sessionStorage.clear()
})

test('sends the viewport and a tab id with the connect params', () => {
  const { _replay: params } = replayParams()

  expect(params.width).toBe(window.innerWidth)
  expect(params.height).toBe(window.innerHeight)
  expect(params.dpr).toBe(window.devicePixelRatio)
  expect(params.tab.length > 0).toBe(true)
})

test('keeps the same tab id for the tab', () => {
  const first = tabId()

  expect(tabId()).toBe(first)
  expect(replayParams()._replay.tab).toBe(first)

  sessionStorage.clear()
  expect(tabId() === first).toBe(false)
})

test('sends the current viewport with clicks and key presses', () => {
  for (const meta of [replayMetadata.click, replayMetadata.keydown, replayMetadata.keyup]) {
    expect(meta()._replay.width).toBe(window.innerWidth)
    expect(meta()._replay.height).toBe(window.innerHeight)
  }
})
