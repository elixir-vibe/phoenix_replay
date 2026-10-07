import { ViewHook } from 'phoenix_live_view'

/** Keeps the current event visible inside the list while playback advances. */
export class EventList extends ViewHook {
  mounted(): void {
    this.reveal()
  }

  updated(): void {
    this.reveal()
  }

  // Scrolls the list itself; `scrollIntoView` would also scroll the page.
  private reveal(): void {
    const item = this.el.querySelector<HTMLElement>('[aria-current]')
    if (!item) return

    const { offsetTop, offsetHeight } = item
    const { scrollTop, clientHeight } = this.el

    if (offsetTop < scrollTop) this.el.scrollTop = offsetTop
    else if (offsetTop + offsetHeight > scrollTop + clientHeight)
      this.el.scrollTop = offsetTop + offsetHeight - clientHeight
  }
}
