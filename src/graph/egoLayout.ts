// Concentric rings, one per hop: the subject at the centre, their direct relations on the inner
// ring, relations of *those* on the next one out.
//
// Laid out, never simulated. A force layout settles somewhere slightly different on every launch,
// and "Acme is the cluster on the left" has to stay true between loads to be worth reading. At
// depth 1 this reduces to exactly the single ring the app has always drawn.

import type { EntityID } from '../../shared/types.ts'
import type { Network, NetworkEdge } from './network.ts'
import type { Point, Size } from './geometry.ts'
import { controlPoint, onCircle, quadPoint, ringRadius } from './geometry.ts'

const SUBJECT_RADIUS = 30
const HORIZONTAL_MARGIN = 140
const VERTICAL_MARGIN = 84
/** How far apart sibling edges between the same pair bow, as a share of their length. */
const PAIR_SPREAD = 0.16

/** Node size falls off with distance, so how far out someone is reads without counting rings. */
const HOP_RADIUS = [SUBJECT_RADIUS, 24, 18, 15]

export interface LayoutNode {
  id: EntityID
  hop: number
  center: Point
  radius: number
  /** Index into the cluster palette — the person's employer. Null when they have none. */
  cluster: number | null
}

export interface LayoutEdge extends NetworkEdge {
  from: EntityID
  to: EntityID
  control: Point
  /** Where this edge's label sits: on its own curve, not on a shared ring. */
  labelPoint: Point
}

export interface EgoLayout {
  nodes: LayoutNode[]
  edges: LayoutEdge[]
  byID: Map<EntityID, LayoutNode>
}

export interface LayoutInput {
  network: Network
  size: Size
  /** Employer cluster index per person, for ordering and colour. */
  cluster: (id: EntityID) => number | null
  /** Display name per person, for a stable order within a ring. */
  name: (id: EntityID) => string
}

export function layoutEgo({ network, size, cluster, name }: LayoutInput): EgoLayout {
  const center: Point = { x: size.width / 2, y: size.height / 2 }
  const maxHop = Math.max(1, ...network.nodes.map((node) => node.hop))
  const outer = ringRadius(size, HORIZONTAL_MARGIN, VERTICAL_MARGIN, SUBJECT_RADIUS * 3)

  const nodes: LayoutNode[] = []
  for (let hop = 0; hop <= maxHop; hop += 1) {
    const ring = network.nodes
      .filter((node) => node.hop === hop)
      // Employer first, so colleagues sit next to each other; then name, then id, so the order is
      // the same on every load and a re-render never reshuffles the ring.
      .sort(
        (a, b) =>
          (cluster(a.id) ?? Number.MAX_SAFE_INTEGER) - (cluster(b.id) ?? Number.MAX_SAFE_INTEGER) ||
          name(a.id).localeCompare(name(b.id)) ||
          a.id.localeCompare(b.id),
      )
    // The outermost ring always lands on `outer`, so depth 1 puts its single ring exactly where
    // the one-hop graph always put it.
    const radius = hop === 0 ? 0 : (outer * hop) / maxHop
    ring.forEach((node, index) => {
      nodes.push({
        id: node.id,
        hop,
        center: hop === 0 ? center : onCircle(center, radius, (2 * Math.PI * index) / ring.length),
        radius: HOP_RADIUS[Math.min(hop, HOP_RADIUS.length - 1)]!,
        cluster: cluster(node.id),
      })
    })
  }

  const byID = new Map(nodes.map((node) => [node.id, node]))
  const edges: LayoutEdge[] = []
  for (const edge of network.edges) {
    const from = byID.get(edge.from)
    const to = byID.get(edge.to)
    if (!from || !to) continue
    // Several relations between the same pair fan out around the straight line rather than
    // stacking on it, so a mutual relation reads as two edges instead of one.
    //
    // The sign flip matters: a perpendicular offset is measured from `from` towards `to`, so the
    // two halves of a mutual relation — stored as a→b and b→a — would bow to the *same* side and
    // land back on top of each other. Both are measured in one canonical direction instead.
    const spread =
      edge.siblings > 1 ? PAIR_SPREAD * (edge.ordinal - (edge.siblings - 1) / 2) * 2 : 0
    const bow = edge.from > edge.to ? -spread : spread
    const control = controlPoint(from.center, to.center, bow)
    edges.push({
      ...edge,
      control,
      labelPoint: quadPoint(from.center, control, to.center, 0.5),
    })
  }

  return { nodes, edges, byID }
}
