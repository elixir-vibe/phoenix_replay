import { ViewHook } from 'phoenix_live_view'

/** What a `<time>` shows: a date and time, a date, or its own text. */
type Format = 'datetime' | 'date' | 'title'

const FORMATS: Record<Exclude<Format, 'title'>, Intl.DateTimeFormatOptions> = {
  datetime: { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' },
  date: { month: 'short', day: 'numeric' }
}

const FULL: Intl.DateTimeFormatOptions = { dateStyle: 'medium', timeStyle: 'medium' }
const UTC: Intl.DateTimeFormatOptions = { ...FULL, timeZone: 'UTC' }

/** A time as `format` shows it in the viewer's time zone, or `null` to keep the text. */
export const localText = (time: Date, format: string): string | null =>
  format in FORMATS
    ? new Intl.DateTimeFormat(undefined, FORMATS[format as keyof typeof FORMATS]).format(time)
    : null

/** The tooltip: the full time in the viewer's time zone, then in UTC. */
export const localTitle = (time: Date): string =>
  `${new Intl.DateTimeFormat(undefined, FULL).format(time)} · ` +
  `${new Intl.DateTimeFormat(undefined, UTC).format(time)} UTC`

/**
 * Shows a `<time datetime>` in the viewer's time zone, as its
 * `data-format` says, with the full time and UTC in its tooltip. The
 * server renders it in UTC; see `PhoenixReplay.Web.Components.Core.local_time/1`.
 */
export class LocalTime extends ViewHook {
  mounted(): void {
    this.localize()
  }

  // A patch puts the server's text back.
  updated(): void {
    this.localize()
  }

  private localize(): void {
    const time = new Date(this.el.getAttribute('datetime') ?? '')
    if (Number.isNaN(time.getTime())) return

    const text = localText(time, this.el.dataset.format ?? 'title')
    if (text !== null) this.el.textContent = text
    this.el.title = localTitle(time)
  }
}
