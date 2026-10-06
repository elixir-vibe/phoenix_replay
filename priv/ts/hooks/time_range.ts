import { ViewHook } from 'phoenix_live_view'

const pad = (number: number): string => String(number).padStart(2, '0')

/** A day and a time of day, as the calendar and the time inputs hold them. */
export interface LocalParts {
  date: string
  time: string
}

/** A UTC time as a day and a time of day in the viewer's time zone. */
export const toLocalParts = (iso: string | undefined): LocalParts | null => {
  const time = new Date(iso ?? '')
  if (!iso || Number.isNaN(time.getTime())) return null

  return {
    date: `${time.getFullYear()}-${pad(time.getMonth() + 1)}-${pad(time.getDate())}`,
    time: `${pad(time.getHours())}:${pad(time.getMinutes())}`
  }
}

/**
 * A day and a time of day in the viewer's time zone as a UTC time, at the
 * start of that minute, or its end with `end`.
 */
export const fromLocalParts = ({ date, time }: LocalParts, end = false): string => {
  const at = new Date(`${date}T${time || (end ? '23:59' : '00:00')}${end ? ':59.999' : ''}`)
  return Number.isNaN(at.getTime()) ? '' : at.toISOString()
}

/** The viewer's time zone and its offset at `time`, such as `", Europe/Berlin (UTC+2)"`. */
export const zoneLabel = (time: Date): string => {
  const minutes = -time.getTimezoneOffset()
  const sign = minutes < 0 ? '−' : '+'
  const hours = Math.floor(Math.abs(minutes) / 60)
  const rest = Math.abs(minutes) % 60
  const offset = minutes === 0 ? 'UTC' : `UTC${sign}${hours}${rest ? `:${pad(rest)}` : ''}`
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone

  return zone ? `, ${zone} (${offset})` : ` (${offset})`
}

/** The calendar's range, `"2026-10-01/2026-10-06"`, as its first and last day. */
const days = (value: string): [string, string] | null => {
  const [first, last] = value.split('/')
  return first && last ? [first, last] : null
}

/**
 * The recording list's range of start times: days on a Cally
 * `<calendar-range>` and the times they start and end, in the viewer's
 * time zone, filled from `data-from` and `data-to` in UTC. Submitting sends
 * `time_range` with `from` and `to` in UTC. It names the time zone in its
 * `[data-time-zone]` element.
 */
export class TimeRange extends ViewHook {
  mounted(): void {
    const from = toLocalParts(this.el.dataset.from)
    const to = toLocalParts(this.el.dataset.to)
    const calendar = this.calendar()

    if (calendar && from && to) {
      calendar.value = `${from.date}/${to.date}`
      calendar.setAttribute('focused-date', to.date)
    }

    this.setTime('from_time', from?.time)
    this.setTime('to_time', to?.time)

    const zone = this.el.querySelector('[data-time-zone]')
    if (zone) zone.textContent = zoneLabel(new Date())

    this.el.addEventListener('submit', this.onSubmit)
  }

  private readonly onSubmit = (event: Event): void => {
    event.preventDefault()
    const range = days(this.calendar()?.value ?? '')
    if (!range) return

    this.pushEvent('time_range', {
      from: fromLocalParts({ date: range[0], time: this.time('from_time') }),
      to: fromLocalParts({ date: range[1], time: this.time('to_time') }, true)
    }).catch(() => undefined)
  }

  private calendar(): (HTMLElement & { value: string }) | null {
    return this.el.querySelector('calendar-range')
  }

  private time(name: string): string {
    return this.el.querySelector<HTMLInputElement>(`input[name="${name}"]`)?.value ?? ''
  }

  private setTime(name: string, value: string | undefined): void {
    const input = this.el.querySelector<HTMLInputElement>(`input[name="${name}"]`)
    if (input && value) input.value = value
  }
}
