import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'

import { confirmClicks } from './dom/confirm'
import { copyLinks } from './dom/copy'
import { searchShortcut } from './dom/shortcut'
import { EventList } from './hooks/event_list'
import { FrameViewport } from './hooks/frame_viewport'
import { Scrubber } from './hooks/scrubber'

const meta = (name: string): string | undefined =>
  document.querySelector<HTMLMetaElement>(`meta[name="${name}"]`)?.content

const liveSocket = new LiveSocket(meta('phoenix-replay-socket') ?? '/live', Socket, {
  params: { _csrf_token: meta('csrf-token') },
  hooks: { EventList, FrameViewport, Scrubber }
})

confirmClicks(window)
copyLinks(window)
searchShortcut(window)
liveSocket.connect()
