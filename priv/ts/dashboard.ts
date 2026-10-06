import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'

import { confirmClicks } from './dom/confirm'
import { copyLinks } from './dom/copy'
import { Floating, floatingTooltips } from './dom/floating'
import { replayInputs } from './client/replay_inputs'
import { searchShortcut } from './dom/shortcut'
import { themeToggle } from './dom/theme'
import { DetailsResizer } from './hooks/details_resizer'
import { EventList } from './hooks/event_list'
import { ExportStage } from './hooks/export_stage'
import { FrameViewport } from './hooks/frame_viewport'
import { LocalTime } from './hooks/local_time'
import { PlayerKeys } from './hooks/player_keys'
import { Pointer } from './hooks/pointer'
import { Scrubber } from './hooks/scrubber'
import { TimeRange } from './hooks/time_range'

const meta = (name: string): string | undefined =>
  document.querySelector<HTMLMetaElement>(`meta[name="${name}"]`)?.content

const liveSocket = new LiveSocket(meta('phoenix-replay-socket') ?? '/live', Socket, {
  params: { _csrf_token: meta('csrf-token') },
  hooks: {
    DetailsResizer,
    EventList,
    ExportStage,
    Floating,
    FrameViewport,
    LocalTime,
    PlayerKeys,
    Pointer,
    Scrubber,
    TimeRange
  }
})

confirmClicks(window)
copyLinks(window)
floatingTooltips(window)
replayInputs(window)
searchShortcut(window)
themeToggle(window)
liveSocket.connect()
