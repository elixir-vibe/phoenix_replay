/**
 * The arithmetic of a turning device, for FrameViewport: whether the
 * recording turned, which way, and the keyframes that turn a frame from
 * one placement to the next while keeping it within its box.
 */

/** How long the device takes to turn, in milliseconds, about as long as a phone's own turn. */
export const TURN_MS = 300
/** Fast at first, then settling, as a phone turns. */
export const TURN_EASING = 'cubic-bezier(0.2, 0, 0, 1)'

// Enough steps that the device keeps within its box at every angle on the way.
const STEPS = 12

/** A frame's recorded size and screen angle. */
export interface Shown {
  width: number
  height: number
  angle: number
}

/** Where a frame was drawn: its offset, turn and scale, and the room its box gave it. */
export interface Placement {
  x: number
  y: number
  degrees: number
  scale: number
  width: number
  height: number
  roomWidth: number
  roomHeight: number
}

const portrait = ({ width, height }: Shown): boolean => height > width

/** Whether the recording went between portrait and landscape. */
export const turned = (previous: Shown, next: Shown): boolean =>
  Boolean(previous.width && next.width) && portrait(previous) !== portrait(next)

/**
 * Which way the device turned, by its screen's angles: the page turns with
 * the device, against the angle's change. Without angles, as most phones
 * turn first, to the left.
 */
export const turnBy = (previous: Shown, next: Shown): number =>
  (((next.angle - previous.angle) % 360) + 360) % 360 === 270 ? 90 : -90

/** A placement as a CSS transform, about the frame's centre. */
export const transform = ({ x, y, degrees, scale }: Placement): string =>
  `translate(${x}px,${y}px) rotate(${degrees}deg) scale(${scale})`

/**
 * The keyframes that turn a frame from one placement to the next. On the
 * way, a turning frame needs more room than at either end, its diagonal's
 * at 45 degrees, so it shrinks to keep within its box. When its layout
 * changed, it fades in over the one it replaced.
 */
export const turnFrames = (from: Placement, to: Placement, fades: boolean): Keyframe[] =>
  Array.from({ length: STEPS + 1 }, (_, step) => {
    const progress = step / STEPS
    const between = (a: number, b: number): number => a + (b - a) * progress
    const degrees = between(from.degrees, to.degrees)
    const radians = (degrees * Math.PI) / 180
    const [cos, sin] = [Math.abs(Math.cos(radians)), Math.abs(Math.sin(radians))]

    // The room the turned frame takes, at this angle.
    const spanWidth = to.width * cos + to.height * sin
    const spanHeight = to.width * sin + to.height * cos
    const scale = Math.min(
      between(from.scale, to.scale),
      to.roomWidth / spanWidth,
      to.roomHeight / spanHeight
    )

    return {
      transform: transform({
        ...to,
        x: between(from.x, to.x),
        y: between(from.y, to.y),
        degrees,
        scale
      }),
      opacity: fades ? Math.min(1, 0.4 + progress * 1.5) : 1,
      offset: progress
    }
  })
