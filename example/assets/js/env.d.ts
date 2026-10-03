import type { LiveSocket } from 'phoenix_live_view'

/** The `phoenix_live_reload` client passed with `phx:live_reload:attached`. */
interface LiveReloader {
  enableServerLogs(): void
  disableServerLogs(): void
  openEditorAtCaller(target: EventTarget | null): void
  openEditorAtDef(target: EventTarget | null): void
}

declare global {
  interface Window {
    liveSocket: InstanceType<typeof LiveSocket>
    liveReloader: LiveReloader
  }

  interface WindowEventMap {
    'phx:live_reload:attached': CustomEvent<LiveReloader>
    'phx:page-loading-start': CustomEvent
    'phx:page-loading-stop': CustomEvent
  }
}
