import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
// Registers Cally's <calendar-range> and <calendar-month> for the time picker.
import 'cally'

import { confirmClicks } from './dom/confirm'
import { copyLinks } from './dom/copy'
import { Floating, floatingTooltips } from './dom/floating'
import { replayInputs } from '../replay/inputs'
import { replayRoot } from '../replay/root'
import { searchShortcut } from './dom/shortcut'
import { themeToggle } from './dom/theme'
import { DetailsResizer } from './player/playback/details_resizer'
import { EventList } from './player/playback/event_list'
import { ExportStage } from './export/stage'
import { FrameMedia } from './player/frame/media'
import { FrameViewport } from './player/frame/viewport'
import { LocalTime } from './dom/local_time'
import { PlayerKeys } from './player/playback/keys'
import { Pointer } from './player/frame/pointer_overlay'
import { Scrubber } from './player/playback/scrubber'
import { TimeRange } from './list/time_range'
import { VisitTimeline } from './player/playback/visit_timeline'

const meta = (name: string): string | undefined =>
  document.querySelector<HTMLMetaElement>(`meta[name="${name}"]`)?.content

const liveSocket = new LiveSocket(meta('phoenix-replay-socket') ?? '/live', Socket, {
  // How far the viewer's time zone is ahead of UTC, in minutes, so charts
  // break at its midnights and hours.
  params: { _csrf_token: meta('csrf-token'), utc_offset: -new Date().getTimezoneOffset() },
  hooks: {
    DetailsResizer,
    EventList,
    ExportStage,
    Floating,
    FrameMedia,
    FrameViewport,
    LocalTime,
    PlayerKeys,
    Pointer,
    Scrubber,
    TimeRange,
    VisitTimeline
  }
})

confirmClicks(window)
copyLinks(window)
floatingTooltips(window)
replayInputs(window)
replayRoot(window)
searchShortcut(window)
themeToggle(window)
liveSocket.connect()
