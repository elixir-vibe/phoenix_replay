/**
 * Index of the last item at or before `ms`, or `-1` when none is. `at`
 * reads an item's time; items are sorted by it.
 */
export const lastAtOrBefore = <T>(
  items: readonly T[],
  ms: number,
  at: (item: T) => number
): number => {
  let low = 0
  let high = items.length - 1
  let found = -1

  while (low <= high) {
    const middle = (low + high) >> 1
    if (at(items[middle] as T) <= ms) {
      found = middle
      low = middle + 1
    } else {
      high = middle - 1
    }
  }

  return found
}

/** Index of the last offset at or before `ms`, or `0`. Offsets are sorted ascending. */
export const indexAt = (offsets: readonly number[], ms: number): number =>
  Math.max(
    lastAtOrBefore(offsets, ms, (offset) => offset),
    0
  )

export const clamp = (value: number, min: number, max: number): number =>
  Math.min(Math.max(value, min), max)
