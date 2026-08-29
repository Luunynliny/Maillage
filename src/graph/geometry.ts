// Shared arithmetic for both graphs. Pure, so both layouts are unit-testable without a browser.

export interface Point {
  x: number
  y: number
}

export interface Size {
  width: number
  height: number
}

/** How much of a pane's half-dimension a label margin may claim before the ring gives way. */
export const GRAPH_MARGIN_SHARE = 0.18

/** Extra hit area around a node, so a small circle is still comfortable to click. */
export const GRAPH_HIT_SLOP = 8

/**
 * The largest ring that fits, treating the margins reserved for labels as caps rather than fixed
 * reserves: a narrow window shrinks its margins before it shrinks the ring below `floor`.
 */
export function ringRadius(
  size: Size,
  horizontal: number,
  vertical: number,
  floor: number,
): number {
  const marginX = Math.min(horizontal, size.width * GRAPH_MARGIN_SHARE)
  const marginY = Math.min(vertical, size.height * GRAPH_MARGIN_SHARE)
  return Math.max(floor, Math.min(size.width / 2 - marginX, size.height / 2 - marginY))
}

/** Angle 0 is straight up and increases clockwise, so labels read around the ring like a clock. */
export function onCircle(center: Point, radius: number, angle: number): Point {
  return {
    x: center.x + radius * Math.sin(angle),
    y: center.y - radius * Math.cos(angle),
  }
}

export function distance(a: Point, b: Point): number {
  return Math.hypot(a.x - b.x, a.y - b.y)
}

/**
 * Pull both ends of an edge back to the rims of the circles it joins, so the line touches each
 * node rather than disappearing underneath it.
 */
export function trimmed(
  from: Point,
  to: Point,
  fromGap: number,
  toGap: number,
): { from: Point; to: Point } {
  const length = distance(from, to)
  if (length === 0) return { from, to }
  const unit = { x: (to.x - from.x) / length, y: (to.y - from.y) / length }
  return {
    from: { x: from.x + unit.x * fromGap, y: from.y + unit.y * fromGap },
    to: { x: to.x - unit.x * toGap, y: to.y - unit.y * toGap },
  }
}

/**
 * The control point of a quadratic curve bowed away from the straight line by `bow` × its length.
 * A bow of 0 gives a control point on the line, which draws as straight.
 */
export function controlPoint(from: Point, to: Point, bow: number): Point {
  const mid = { x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 }
  if (bow === 0) return mid
  const length = distance(from, to)
  if (length === 0) return mid
  const perpendicular = { x: -(to.y - from.y) / length, y: (to.x - from.x) / length }
  return {
    x: mid.x + perpendicular.x * bow * length,
    y: mid.y + perpendicular.y * bow * length,
  }
}

export function quadPoint(from: Point, control: Point, to: Point, t: number): Point {
  const u = 1 - t
  return {
    x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
    y: u * u * from.y + 2 * u * t * control.y + t * t * to.y,
  }
}

export function quadPath(from: Point, control: Point, to: Point): string {
  return `M ${round(from.x)} ${round(from.y)} Q ${round(control.x)} ${round(control.y)} ${round(to.x)} ${round(to.y)}`
}

/**
 * A filled triangle at the tip of an edge, aimed along the curve's own tangent there rather than
 * along the straight chord — otherwise an arrowhead on a bowed edge points somewhere the line
 * never goes.
 */
export function arrowhead(at: Point, approaching: Point, size = 7, spread = 26): string {
  const heading = Math.atan2(at.y - approaching.y, at.x - approaching.x)
  const wing = (spread * Math.PI) / 180
  const left = {
    x: at.x - size * Math.cos(heading - wing),
    y: at.y - size * Math.sin(heading - wing),
  }
  const right = {
    x: at.x - size * Math.cos(heading + wing),
    y: at.y - size * Math.sin(heading + wing),
  }
  return `M ${round(at.x)} ${round(at.y)} L ${round(left.x)} ${round(left.y)} L ${round(right.x)} ${round(right.y)} Z`
}

function round(value: number): number {
  return Math.round(value * 100) / 100
}
