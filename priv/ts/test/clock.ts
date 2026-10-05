import FakeTimers from '@sinonjs/fake-timers'

/** A clock the test moves on by hand. */
export type Clock = ReturnType<typeof FakeTimers.install>

/**
 * Replaces the page's timers, `Date` and `performance.now` with a clock
 * that stands still until the test ticks it, so debounces and quiet
 * periods run at once and in a set order. Uninstall it after the test,
 * before the runner's own timers need the real ones.
 */
export const fakeClock = (): Clock =>
  FakeTimers.install({
    toFake: ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval', 'Date', 'performance']
  })
