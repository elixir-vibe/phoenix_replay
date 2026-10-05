import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'

import { confirmClicks } from './dom/confirm'
import { copyLinks } from './dom/copy'
import { replayInputs } from './dom/replay_inputs'
import { searchShortcut } from './dom/shortcut'
import { EventList } from './hooks/event_list'
import { FrameViewport } from './hooks/frame_viewport'
import { Pointer } from './hooks/pointer'
import { Scrubber } from './hooks/scrubber'

const meta = (name: string): string | undefined =>
  document.querySelector<HTMLMetaElement>(`meta[name="${name}"]`)?.content

const liveSocket = new LiveSocket(meta('phoenix-replay-socket') ?? '/live', Socket, {
  params: { _csrf_token: meta('csrf-token') },
  hooks: { EventList, FrameViewport, Pointer, Scrubber }
})

confirmClicks(window)
copyLinks(window)
replayInputs(window)
searchShortcut(window)
liveSocket.connect()
