import { ViewHook } from 'phoenix_live_view'

const pad = (number: number): string => String(number).padStart(2, '0')

/** A UTC time as a `datetime-local` input's value, in the viewer's time zone. */
export const toLocalInput = (iso: string | undefined): string => {
  const time = new Date(iso ?? '')
  if (!iso || Number.isNaN(time.getTime())) return ''

  return (
    `${time.getFullYear()}-${pad(time.getMonth() + 1)}-${pad(time.getDate())}` +
    `T${pad(time.getHours())}:${pad(time.getMinutes())}`
  )
}

/** A `datetime-local` input's value, in the viewer's time zone, as a UTC time. */
export const fromLocalInput = (value: string): string => {
  const time = new Date(value)
  return value && !Number.isNaN(time.getTime()) ? time.toISOString() : ''
}

/** The viewer's time zone and its offset at `time`, such as `"Europe/Berlin, UTC+2"`. */
export const zoneLabel = (time: Date): string => {
  const minutes = -time.getTimezoneOffset()
  const sign = minutes < 0 ? '−' : '+'
  const hours = Math.floor(Math.abs(minutes) / 60)
  const rest = Math.abs(minutes) % 60
  const offset = minutes === 0 ? 'UTC' : `UTC${sign}${hours}${rest ? `:${pad(rest)}` : ''}`
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone

  return zone ? `, ${zone} (${offset})` : ` (${offset})`
}

/**
 * The recording list's range of start times. Its `datetime-local` inputs
 * are in the viewer's time zone, filled from `data-from` and `data-to` in
 * UTC; submitting sends `time_range` with `from` and `to` in UTC, either
 * blank. It names the time zone in its `[data-time-zone]` element.
 */
export class TimeRange extends ViewHook {
  mounted(): void {
    for (const name of ['from', 'to'] as const) {
      const input = this.input(name)
      if (input) input.value = toLocalInput(this.el.dataset[name])
    }

    const zone = this.el.querySelector('[data-time-zone]')
    if (zone) zone.textContent = zoneLabel(new Date())

    this.el.addEventListener('submit', this.onSubmit)
  }

  private readonly onSubmit = (event: Event): void => {
    event.preventDefault()

    this.pushEvent('time_range', {
      from: fromLocalInput(this.input('from')?.value ?? ''),
      to: fromLocalInput(this.input('to')?.value ?? '')
    }).catch(() => undefined)
  }

  private input(name: string): HTMLInputElement | null {
    return this.el.querySelector<HTMLInputElement>(`input[name="${name}"]`)
  }
}
