// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import 'phoenix_html'
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from 'phoenix'
import { hooks as colocatedHooks } from 'phoenix-colocated/example'
import { LiveSocket } from 'phoenix_live_view'
import { replayMetadata, replayParams, replayRecorder } from 'phoenix_replay'

import topbar from '../vendor/topbar'
import { ClientSearch } from './client_search'

const csrfToken = document
  .querySelector<HTMLMetaElement>("meta[name='csrf-token']")
  ?.getAttribute('content')

const liveSocket = new LiveSocket('/live', Socket, {
  longPollFallbackMs: 2500,
  params: () => ({ _csrf_token: csrfToken, ...replayParams() }),
  metadata: replayMetadata,
  hooks: { ...colocatedHooks, ClientSearch }
})

// The theme the server chose applies at once, and the cookie keeps it for
// the next page load; see ExampleWeb.Theme.
window.addEventListener('phx:theme', (event) => {
  const { theme } = (event as CustomEvent<{ theme: string }>).detail
  document.documentElement.dataset.theme = theme
  document.cookie = `theme=${theme}; path=/; max-age=31536000; samesite=lax`
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: '#29d' }, shadowColor: 'rgba(0, 0, 0, .3)' })
window.addEventListener('phx:page-loading-start', () => topbar.show(300))
window.addEventListener('phx:page-loading-stop', () => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()
replayRecorder(liveSocket)

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (import.meta.env.DEV) {
  window.addEventListener('phx:live_reload:attached', ({ detail: reloader }) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown: string | null = null
    window.addEventListener('keydown', (e) => (keyDown = e.key))
    window.addEventListener('keyup', () => (keyDown = null))
    window.addEventListener(
      'click',
      (e) => {
        if (keyDown === 'c') {
          e.preventDefault()
          e.stopImmediatePropagation()
          reloader.openEditorAtCaller(e.target)
        } else if (keyDown === 'd') {
          e.preventDefault()
          e.stopImmediatePropagation()
          reloader.openEditorAtDef(e.target)
        }
      },
      true
    )

    window.liveReloader = reloader
  })
}
