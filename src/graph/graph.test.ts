import { describe, expect, test } from 'vitest'
import type { Person, VaultSnapshot } from '../../shared/types.ts'
import { bubbleRadius, packBubbles } from './bubblePacking.ts'
import { layoutEgo } from './egoLayout.ts'
import {
  arrowhead,
  controlPoint,
  distance,
  onCircle,
  ringRadii,
  ringRadius,
  trimmed,
} from './geometry.ts'
import { traverse } from './network.ts'

const SIZE = { width: 800, height: 600 }

function person(id: string, relations: [string, string][] = []): Person {
  return {
    kind: 'person',
    id,
    firstname: id,
    placeholder: false,
    projects: [],
    relations: relations.map(([to, label]) => ({ to, label })),
    body: '',
  }
}

function vault(people: Person[]): VaultSnapshot {
  return {
    people: Object.fromEntries(people.map((p) => [p.id, p])),
    organizations: {},
    projects: {},
    logoIDs: { person: [], organization: [], project: [] },
    issues: [],
  }
}

const plain = (snapshot: VaultSnapshot, root: string, depth: number) =>
  layoutEgo({
    network: traverse(snapshot, root, depth),
    size: SIZE,
    cluster: () => null,
    name: (id) => id,
  })

describe('geometry', () => {
  test('ringRadius reserves the margins it is given when there is room', () => {
    expect(ringRadius({ width: 1000, height: 1000 }, 140, 84, 90)).toBe(500 - 140)
  })

  test('a narrow pane shrinks its margins before shrinking the ring', () => {
    // 18% of 400 is 72, less than the 140 asked for, so the cap applies instead.
    expect(ringRadius({ width: 400, height: 1000 }, 140, 84, 90)).toBe(200 - 72)
  })

  test('the ring never drops below its floor', () => {
    expect(ringRadius({ width: 100, height: 100 }, 140, 84, 90)).toBe(90)
  })

  test('angle 0 is straight up and angles increase clockwise', () => {
    const center = { x: 0, y: 0 }
    expect(onCircle(center, 10, 0)).toEqual({ x: 0, y: -10 })
    const quarter = onCircle(center, 10, Math.PI / 2)
    expect(quarter.x).toBeCloseTo(10)
    expect(quarter.y).toBeCloseTo(0)
  })

  test('trimmed returns points on each rim, not the centres', () => {
    const result = trimmed({ x: 0, y: 0 }, { x: 100, y: 0 }, 10, 20)
    expect(result.from).toEqual({ x: 10, y: 0 })
    expect(result.to).toEqual({ x: 80, y: 0 })
  })

  test('a zero bow leaves the control point on the line', () => {
    expect(controlPoint({ x: 0, y: 0 }, { x: 10, y: 0 }, 0)).toEqual({ x: 5, y: 0 })
  })

  test('a bow pushes the control point perpendicular to the line', () => {
    const control = controlPoint({ x: 0, y: 0 }, { x: 10, y: 0 }, 0.5)
    expect(control.x).toBeCloseTo(5)
    expect(Math.abs(control.y)).toBeCloseTo(5)
  })

  test('the arrowhead is a closed triangle', () => {
    const path = arrowhead({ x: 10, y: 0 }, { x: 0, y: 0 })
    expect(path.startsWith('M 10 0')).toBe(true)
    expect(path.endsWith('Z')).toBe(true)
  })

  test('distance is euclidean', () => {
    expect(distance({ x: 0, y: 0 }, { x: 3, y: 4 })).toBe(5)
  })
})

describe('traverse', () => {
  const snapshot = vault([
    person('root', [['a', 'knows']]),
    person('a', [['b', 'knows']]),
    person('b', [['c', 'knows']]),
    person('c'),
    person('unrelated'),
  ])

  test('depth 1 reaches only direct relations', () => {
    expect(
      traverse(snapshot, 'root', 1)
        .nodes.map((n) => n.id)
        .sort(),
    ).toEqual(['a', 'root'])
  })

  test('depth 2 reaches a relation of a relation', () => {
    expect(
      traverse(snapshot, 'root', 2)
        .nodes.map((n) => n.id)
        .sort(),
    ).toEqual(['a', 'b', 'root'])
  })

  test('reachability ignores direction — an inbound relation still connects', () => {
    const inbound = vault([person('root'), person('a', [['root', 'knows']])])
    expect(traverse(inbound, 'root', 1).nodes).toHaveLength(2)
  })

  test('every hop is recorded, so the layout knows which ring a node is on', () => {
    const hops = new Map(traverse(snapshot, 'root', 3).nodes.map((n) => [n.id, n.hop]))
    expect([hops.get('root'), hops.get('a'), hops.get('b'), hops.get('c')]).toEqual([0, 1, 2, 3])
  })

  test('an unreachable person is never drawn', () => {
    expect(traverse(snapshot, 'root', 3).nodes.map((n) => n.id)).not.toContain('unrelated')
  })

  test('edges between two neighbours are included — the reason multi-hop exists', () => {
    const triangle = vault([
      person('root', [
        ['a', 'knows'],
        ['b', 'knows'],
      ]),
      person('a', [['b', 'works with']]),
      person('b'),
    ])
    const edges = traverse(triangle, 'root', 1).edges
    expect(edges).toHaveLength(3)
    expect(edges.some((edge) => edge.from === 'a' && edge.to === 'b')).toBe(true)
  })

  test('several relations between one pair are numbered so they can bow apart', () => {
    const mutual = vault([
      person('root', [['a', 'manager of']]),
      person('a', [['root', 'reports to']]),
    ])
    const edges = traverse(mutual, 'root', 1).edges
    expect(edges.map((edge) => edge.siblings)).toEqual([2, 2])
    expect(edges.map((edge) => edge.ordinal).sort()).toEqual([0, 1])
  })

  test('a lone relation gets no siblings and therefore no bow', () => {
    expect(traverse(snapshot, 'root', 1).edges[0]!.siblings).toBe(1)
  })

  test('a dangling relation target is not walked to', () => {
    const dangling = vault([person('root', [['ghost', 'knows']])])
    expect(traverse(dangling, 'root', 2).nodes.map((n) => n.id)).toEqual(['root'])
  })

  test('a self-relation neither adds a node nor an edge', () => {
    const selfish = vault([person('root', [['root', 'knows']])])
    const network = traverse(selfish, 'root', 2)
    expect(network.nodes).toHaveLength(1)
    expect(network.edges).toHaveLength(0)
  })

  test('a root with no file at all yields an empty network', () => {
    expect(traverse(snapshot, 'nobody', 2).nodes).toEqual([])
  })

  test('the size cap truncates and says how many it left out', () => {
    const hub = person(
      'root',
      Array.from({ length: 20 }, (_, index) => [`p${index}`, 'knows'] as [string, string]),
    )
    const crowd = vault([hub, ...Array.from({ length: 20 }, (_, i) => person(`p${i}`))])
    const network = traverse(crowd, 'root', 1, 5)
    expect(network.nodes).toHaveLength(5)
    expect(network.omitted).toBe(16)
  })
})

describe('layoutEgo', () => {
  const snapshot = vault([
    person('root', [
      ['a', 'knows'],
      ['b', 'knows'],
    ]),
    person('a', [['c', 'knows']]),
    person('b'),
    person('c'),
  ])

  const layout1 = plain(snapshot, 'root', 1)

  test('the subject sits at the centre of the pane', () => {
    expect(layout1.byID.get('root')!.center).toEqual({ x: 400, y: 300 })
  })

  test('depth 1 puts everyone on one ring around the subject', () => {
    // The ring is an ellipse, not a circle: a pane is wider than it is tall, and a circle
    // inscribed in it wastes a third of the width on each side.
    const { rx, ry } = ringRadii(SIZE, 140, 84, 90)
    for (const node of layout1.nodes.filter((n) => n.hop === 1)) {
      const dx = (node.center.x - 400) / rx
      const dy = (node.center.y - 300) / ry
      expect(Math.hypot(dx, dy)).toBeCloseTo(1)
    }
  })

  test('the ring uses the width of a wide pane, not just its height', () => {
    const wide = layoutEgo({
      network: traverse(
        vault([
          person('root', [
            ['a', 'knows'],
            ['b', 'knows'],
            ['c', 'knows'],
            ['d', 'knows'],
          ]),
          person('a'),
          person('b'),
          person('c'),
          person('d'),
        ]),
        'root',
        1,
      ),
      size: { width: 1400, height: 600 },
      cluster: () => null,
      name: (id) => id,
    })
    const spread =
      Math.max(...wide.nodes.map((n) => n.center.x)) -
      Math.min(...wide.nodes.map((n) => n.center.x))
    expect(spread).toBeGreaterThan(600)
  })

  test('a second hop lands outside the first', () => {
    const layout = plain(snapshot, 'root', 2)
    const ringOf = (hop: number) =>
      distance(layout.nodes.find((n) => n.hop === hop)!.center, { x: 400, y: 300 })
    expect(ringOf(2)).toBeGreaterThan(ringOf(1))
  })

  test('a label sits off the midpoint, where spokes do not all cross', () => {
    // Every spoke's true midpoint is the same distance from the subject, so at 0.5 the labels
    // would all land on one small circle and pile onto each other.
    const edge = layout1.edges[0]!
    const from = layout1.byID.get(edge.from)!.center
    const to = layout1.byID.get(edge.to)!.center
    const midpoint = { x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 }
    expect(distance(edge.labelPoint, midpoint)).toBeGreaterThan(4)
  })

  test('nodes shrink as they get further out, so distance reads without counting rings', () => {
    const layout = plain(snapshot, 'root', 2)
    const radiusOf = (hop: number) => layout.nodes.find((n) => n.hop === hop)!.radius
    expect(radiusOf(0)).toBeGreaterThan(radiusOf(1))
    expect(radiusOf(1)).toBeGreaterThan(radiusOf(2))
  })

  test('one node per person, however many relations they have', () => {
    const many = vault([
      person('root', [
        ['a', 'manager of'],
        ['a', 'friend of'],
      ]),
      person('a', [['root', 'reports to']]),
    ])
    expect(plain(many, 'root', 1).nodes).toHaveLength(2)
  })

  test('the same vault lays out identically every time', () => {
    const once = plain(snapshot, 'root', 2)
    const twice = plain(snapshot, 'root', 2)
    expect(JSON.stringify(twice.nodes)).toBe(JSON.stringify(once.nodes))
  })

  test('colleagues are placed next to each other', () => {
    const employed = vault([
      person('root', [
        ['a', 'knows'],
        ['b', 'knows'],
        ['c', 'knows'],
      ]),
      person('a'),
      person('b'),
      person('c'),
    ])
    // a and c share an employer, b does not; a and c must end up adjacent on the ring.
    const layout = layoutEgo({
      network: traverse(employed, 'root', 1),
      size: SIZE,
      cluster: (id) => (id === 'b' ? 1 : 0),
      name: (id) => id,
    })
    const ring = layout.nodes.filter((n) => n.hop === 1).map((n) => n.id)
    expect(ring).toEqual(['a', 'c', 'b'])
  })

  test('a lone relation draws straight; siblings bow apart', () => {
    const lone = plain(snapshot, 'root', 1).edges[0]!
    const midpoint = { x: 400, y: 300 }
    expect(distance(lone.control, midpoint)).toBeGreaterThan(0)

    const mutual = vault([
      person('root', [['a', 'manager of']]),
      person('a', [['root', 'reports to']]),
    ])
    const [first, second] = plain(mutual, 'root', 1).edges
    expect(distance(first!.control, second!.control)).toBeGreaterThan(1)
  })

  test('every edge carries its own label point, not a shared ring position', () => {
    const layout = plain(snapshot, 'root', 2)
    const points = layout.edges.map((edge) => `${edge.labelPoint.x},${edge.labelPoint.y}`)
    expect(new Set(points).size).toBe(points.length)
  })

  test('an isolated person lays out as a single centred node', () => {
    const layout = plain(vault([person('root')]), 'root', 3)
    expect(layout.nodes).toHaveLength(1)
    expect(layout.edges).toHaveLength(0)
  })
})

describe('packBubbles', () => {
  const groups = (counts: number[]) =>
    counts.map((headcount, index) => ({
      id: `org-${index}`,
      label: `Org ${index}`,
      headcount,
    }))

  test('area grows with headcount, not radius', () => {
    const oneToFour = bubbleRadius(4) / bubbleRadius(1)
    expect(oneToFour).toBeLessThan(4)
    expect(bubbleRadius(9)).toBeGreaterThan(bubbleRadius(4))
  })

  test('the radius is clamped so one huge company does not swallow the pane', () => {
    expect(bubbleRadius(10_000)).toBe(bubbleRadius(100_000))
  })

  test('one bubble per group', () => {
    expect(packBubbles(groups([3, 1, 7]), SIZE)).toHaveLength(3)
  })

  test('no two bubbles overlap', () => {
    for (let count = 1; count <= 12; count += 1) {
      const packed = packBubbles(groups(Array.from({ length: count }, (_, i) => i + 1)), SIZE)
      for (const a of packed) {
        for (const b of packed) {
          if (a === b) continue
          expect(distance(a.center, b.center)).toBeGreaterThan(a.radius + b.radius - 1)
        }
      }
    }
  })

  test('the biggest company claims the centre', () => {
    const packed = packBubbles(groups([2, 9, 3]), SIZE)
    const middle = { x: SIZE.width / 2, y: SIZE.height / 2 }
    const nearest = [...packed].sort(
      (a, b) => distance(a.center, middle) - distance(b.center, middle),
    )
    expect(nearest[0]!.headcount).toBe(9)
  })

  test('the unaffiliated bucket is placed last however many people are in it', () => {
    // Bubbles come back in placement order, and the first placed is the one that claims the
    // middle of the cluster. "No employer" is not a company, so it never gets to be the subject
    // of the picture even when it is the biggest circle in it.
    const packed = packBubbles(
      [{ id: null, label: 'No employer', headcount: 40 }, ...groups([2, 5])],
      SIZE,
    )
    expect(packed.at(-1)!.id).toBeNull()
    expect(packed[0]!.id).toBe('org-1')
  })

  test('packing is deterministic', () => {
    const once = packBubbles(groups([4, 4, 2, 9]), SIZE)
    expect(JSON.stringify(packBubbles(groups([4, 4, 2, 9]), SIZE))).toBe(JSON.stringify(once))
  })

  test('a lone company is centred and not blown up past the upscale cap', () => {
    const [only] = packBubbles(groups([3]), SIZE)
    expect(only!.center).toEqual({ x: 400, y: 300 })
    expect(only!.radius).toBeLessThanOrEqual(bubbleRadius(3) * 1.35 + 0.001)
  })

  test('an empty vault packs into nothing', () => {
    expect(packBubbles([], SIZE)).toEqual([])
  })
})
