import { describe, expect, test } from 'volt:test'

import { clamp, indexAt } from './timeline'

describe('indexAt', () => {
  const offsets = [0, 5, 1000, 1001, 2000]

  test.each([
    [0, 0],
    [4, 0],
    [5, 1],
    [999, 1],
    [1000, 2],
    [1500, 3],
    [2000, 4],
    [9999, 4]
  ])('%d ms is event %d', (ms, index) => {
    expect(indexAt(offsets, Number(ms))).toBe(Number(index))
  })

  test('handles empty and single-event recordings', () => {
    expect(indexAt([], 100)).toBe(0)
    expect(indexAt([0], 100)).toBe(0)
  })

  test('picks the last of events sharing an offset', () => {
    expect(indexAt([0, 10, 10, 10, 20], 10)).toBe(3)
  })
})

test('clamp', () => {
  expect(clamp(-1, 0, 1)).toBe(0)
  expect(clamp(0.5, 0, 1)).toBe(0.5)
  expect(clamp(2, 0, 1)).toBe(1)
})
