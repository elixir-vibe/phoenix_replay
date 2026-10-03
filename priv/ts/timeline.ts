/** Index of the last offset at or before `ms`. Offsets are sorted ascending. */
export const indexAt = (offsets: readonly number[], ms: number): number => {
  let low = 0
  let high = offsets.length - 1

  while (low < high) {
    const middle = Math.ceil((low + high) / 2)
    if ((offsets[middle] ?? 0) <= ms) low = middle
    else high = middle - 1
  }

  return Math.max(low, 0)
}

export const clamp = (value: number, min: number, max: number): number =>
  Math.min(Math.max(value, min), max)
