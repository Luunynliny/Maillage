// One circle per employer, area proportional to headcount, packed by a deterministic spiral sweep.
// No physics, no relaxation, no randomness: identical input always produces an identical picture,
// which is the whole point of a view whose job is "Acme is the big one".

import type { Point, Size } from './geometry.ts'
import { distance } from './geometry.ts'

const MIN_RADIUS = 44
const MAX_RADIUS = 150
const GROWTH = 26
const GAP = 12
/** A vault with one company should not balloon to fill the window. */
const MAX_UPSCALE = 1.35
const SWEEP_ANGLES = 90
const SWEEP_STEP = 3

export interface BubbleInput {
  id: string | null
  label: string
  headcount: number
}

export interface Bubble extends BubbleInput {
  center: Point
  radius: number
}

/**
 * Square-root growth ties *area* to headcount. Tying the radius to it instead would make a circle
 * of twice the radius look like twice the people when it is four times the ink.
 */
export function bubbleRadius(headcount: number): number {
  return Math.min(MIN_RADIUS + GROWTH * Math.sqrt(Math.max(0, headcount - 1)), MAX_RADIUS)
}

export function packBubbles(groups: BubbleInput[], size: Size): Bubble[] {
  if (!groups.length) return []

  // Biggest first so the largest circle claims the centre; the unaffiliated bucket is last
  // regardless of size, since "no employer" is not a company and should not sit in the middle.
  const ordered = [...groups].sort((a, b) => {
    if ((a.id === null) !== (b.id === null)) return a.id === null ? 1 : -1
    return b.headcount - a.headcount || a.label.localeCompare(b.label)
  })

  const placed: Bubble[] = []
  for (const group of ordered) {
    const radius = bubbleRadius(group.headcount)
    placed.push({ ...group, radius, center: place(radius, placed) })
  }
  return fit(placed, size)
}

/** Sweep angles at a growing distance from the origin until one clears everything placed so far. */
function place(radius: number, placed: Bubble[]): Point {
  if (!placed.length) return { x: 0, y: 0 }
  const first = placed[0]!
  let reach = first.radius + radius + GAP
  // The loosest possible packing is every circle in a line, so this always terminates.
  const limit = placed.reduce((total, bubble) => total + 2 * bubble.radius + GAP, reach)

  while (reach <= limit) {
    for (let step = 0; step < SWEEP_ANGLES; step += 1) {
      const angle = (2 * Math.PI * step) / SWEEP_ANGLES
      const candidate = { x: Math.cos(angle) * reach, y: Math.sin(angle) * reach }
      const clears = placed.every(
        (bubble) => distance(candidate, bubble.center) >= bubble.radius + radius + GAP - 0.001,
      )
      if (clears) return candidate
    }
    reach += SWEEP_STEP
  }
  return { x: limit, y: 0 }
}

/** Centre the finished cluster in the pane and scale it to fit, never past `MAX_UPSCALE`. */
function fit(bubbles: Bubble[], size: Size): Bubble[] {
  const left = Math.min(...bubbles.map((b) => b.center.x - b.radius))
  const right = Math.max(...bubbles.map((b) => b.center.x + b.radius))
  const top = Math.min(...bubbles.map((b) => b.center.y - b.radius))
  const bottom = Math.max(...bubbles.map((b) => b.center.y + b.radius))

  const scale = Math.min(
    size.width / Math.max(1, right - left),
    size.height / Math.max(1, bottom - top),
    MAX_UPSCALE,
  )
  const midX = (left + right) / 2
  const midY = (top + bottom) / 2

  return bubbles.map((bubble) => ({
    ...bubble,
    radius: bubble.radius * scale,
    center: {
      x: size.width / 2 + (bubble.center.x - midX) * scale,
      y: size.height / 2 + (bubble.center.y - midY) * scale,
    },
  }))
}
