// The relationship view.
//
// The old ego graph answered exactly one question — "who does this person know?" — with one ring,
// no way in, and no way out. This answers the questions that actually get asked of a personal CRM:
// who is two steps away, which of my contacts know each other, how would I reach someone, and
// which of these edges are the kind I care about right now.
//
// Still laid out rather than simulated. Depth, filters and search change what is *lit*, never
// where anything sits, so the picture stays the same picture while you interrogate it.

import { useEffect, useMemo, useRef, useState } from 'react'
import type { EntityID, Person } from '../../shared/types.ts'
import { displayName } from '../../shared/types.ts'
import { EmptyState, EntityAvatar, Icon, Pill, SearchField } from '../design/components.tsx'
import type { LayoutEdge, LayoutNode } from '../graph/egoLayout.ts'
import { layoutEgo } from '../graph/egoLayout.ts'
import { arrowhead, distance, quadPath, trimmed } from '../graph/geometry.ts'
import { MAX_DEPTH, traverse } from '../graph/network.ts'
import type { EntityRef } from '../vault/derived.ts'
import { clusterIndexOf } from '../vault/derived.ts'
import { useVault } from '../vault/store.tsx'
import { clusterColor } from './panes.tsx'
import { useElementSize } from './useElementSize.ts'

/**
 * Beyond this many edges, showing every label at once turns the middle of the graph into a wall of
 * overlapping words. Past it, labels appear for whatever is lit — hover a node, or filter by a
 * relation — which is when you actually want to read them.
 */
const LABELS_ALWAYS_BELOW = 10
const EDGE_GAP = 4

export function NetworkGraph({
  person,
  onSelect,
  onAddRelation,
}: {
  person: Person
  onSelect: (ref: EntityRef | null) => void
  onAddRelation: (id: string) => void
}) {
  const vault = useVault()
  const [paneRef, size] = useElementSize()
  const [depth, setDepth] = useState(1)
  const [mutedLabels, setMutedLabels] = useState<Set<string>>(new Set())
  const [mutedOrgs, setMutedOrgs] = useState<Set<string>>(new Set())
  const [query, setQuery] = useState('')
  const [hovered, setHovered] = useState<EntityID | null>(null)
  const [trail, setTrail] = useState<EntityID[]>([person.id])

  const network = useMemo(
    () => traverse(vault.snapshot, person.id, depth),
    [vault.snapshot, person.id, depth],
  )

  const layout = useMemo(
    () =>
      size.width
        ? layoutEgo({
            network,
            size,
            cluster: (id) => {
              const candidate = vault.snapshot.people[id]
              return candidate ? clusterIndexOf(vault.groups, candidate) : null
            },
            name: (id) => {
              const candidate = vault.snapshot.people[id]
              return candidate ? displayName(candidate) : id
            },
          })
        : { nodes: [], edges: [], byID: new Map<EntityID, LayoutNode>() },
    [network, size, vault.snapshot, vault.groups],
  )

  // Where you have been, so re-rooting is exploration rather than losing your place.
  useEffect(() => {
    setTrail((current) => (current.at(-1) === person.id ? current : [...current, person.id]))
  }, [person.id])

  const labels = useMemo(() => tally(network.edges.map((edge) => edge.label)), [network])
  const organizations = useMemo(() => {
    const counts = tally(
      network.nodes.map((node) => vault.snapshot.people[node.id]?.organization ?? ''),
    )
    return counts.filter(([id]) => id && vault.snapshot.organizations[id])
  }, [network, vault.snapshot])

  const matches = useMemo(() => {
    const needle = query.trim().toLowerCase()
    if (!needle) return null
    return new Set(
      network.nodes
        .map((node) => vault.snapshot.people[node.id])
        .filter(
          (candidate): candidate is Person =>
            !!candidate &&
            [displayName(candidate), candidate.role, candidate.email, candidate.id]
              .filter(Boolean)
              .some((field) => field!.toLowerCase().includes(needle)),
        )
        .map((candidate) => candidate.id),
    )
  }, [query, network, vault.snapshot])

  const nodeLit = (id: EntityID): boolean => {
    const candidate = vault.snapshot.people[id]
    if (candidate?.organization && mutedOrgs.has(candidate.organization)) return false
    if (matches && !matches.has(id)) return false
    if (hovered) return hovered === id || isAdjacent(layout.edges, hovered, id)
    return true
  }

  const edgeLit = (edge: LayoutEdge): boolean => {
    if (mutedLabels.has(edge.label)) return false
    if (!nodeLit(edge.from) || !nodeLit(edge.to)) return false
    if (hovered) return edge.from === hovered || edge.to === hovered
    return true
  }

  const showEveryLabel = layout.edges.length <= LABELS_ALWAYS_BELOW

  return (
    <div className="network">
      <div className="network-toolbar">
        <div className="toolbar-group" role="group" aria-label="Depth">
          <span className="toolbar-label">Depth</span>
          {Array.from({ length: MAX_DEPTH }, (_, index) => index + 1).map((level) => (
            <button
              key={level}
              type="button"
              className={`segment${depth === level ? ' segment-on' : ''}`}
              onClick={() => setDepth(level)}
              title={
                level === 1
                  ? 'Direct relations only'
                  : `Everyone within ${level} steps, and every edge between them`
              }
            >
              {level}
            </button>
          ))}
        </div>

        <div className="toolbar-search">
          <SearchField value={query} onChange={setQuery} placeholder="Highlight someone…" />
        </div>

        {trail.length > 1 && (
          <nav className="breadcrumbs" aria-label="Where you have been">
            {trail.slice(-4).map((id, index, shown) => (
              <button
                key={`${id}-${index}`}
                type="button"
                className="crumb"
                disabled={index === shown.length - 1}
                onClick={() => {
                  setTrail(trail.slice(0, trail.indexOf(id) + 1))
                  onSelect({ kind: 'person', id })
                }}
              >
                {vault.snapshot.people[id] ? displayName(vault.snapshot.people[id]!) : id}
              </button>
            ))}
          </nav>
        )}
      </div>

      {(labels.length > 0 || organizations.length > 0) && (
        <div className="network-legend">
          <span className="toolbar-label">
            <Icon name="filter" size={11} />
          </span>
          {labels.map(([label, count]) => (
            <Pill
              key={label}
              color={mutedLabels.has(label) ? 'var(--text-faint)' : 'var(--accent)'}
              onClick={() => setMutedLabels(toggled(mutedLabels, label))}
              title={mutedLabels.has(label) ? 'Show these relations' : 'Dim these relations'}
            >
              {label} <span className="legend-count">{count}</span>
            </Pill>
          ))}
          {organizations.map(([id, count]) => {
            const organization = vault.snapshot.organizations[id]!
            const index = vault.groups.findIndex((group) => group.organization?.id === id)
            return (
              <Pill
                key={id}
                color={mutedOrgs.has(id) ? 'var(--text-faint)' : clusterColor(index)}
                onClick={() => setMutedOrgs(toggled(mutedOrgs, id))}
                title={mutedOrgs.has(id) ? 'Show these people' : 'Dim these people'}
              >
                {displayName(organization)} <span className="legend-count">{count}</span>
              </Pill>
            )
          })}
        </div>
      )}

      <div className="network-canvas" ref={paneRef}>
        {!network.edges.length && network.nodes.length <= 1 ? (
          <EmptyState
            icon="person"
            title="No relations yet"
            message={`Nothing points at ${displayName(person)}, and they point at nobody. A relation is written to this person's file only — the other end is derived.`}
            action={
              <button
                className="button button-primary"
                type="button"
                onClick={() => onAddRelation(person.id)}
              >
                Add a relation
              </button>
            }
          />
        ) : (
          <Canvas
            size={size}
            layout={layout}
            rootID={person.id}
            hovered={hovered}
            setHovered={setHovered}
            nodeLit={nodeLit}
            edgeLit={edgeLit}
            showEveryLabel={showEveryLabel}
            mutedLabels={mutedLabels}
            onSelect={onSelect}
          />
        )}

        {network.omitted > 0 && (
          <p className="network-note">
            {network.omitted} more within {depth} steps, not drawn — the picture stops being
            readable long before it stops being complete.
          </p>
        )}
      </div>
    </div>
  )
}

// -- the drawing -------------------------------------------------------------------------------

function Canvas({
  size,
  layout,
  rootID,
  hovered,
  setHovered,
  nodeLit,
  edgeLit,
  showEveryLabel,
  mutedLabels,
  onSelect,
}: {
  size: { width: number; height: number }
  layout: { nodes: LayoutNode[]; edges: LayoutEdge[]; byID: Map<EntityID, LayoutNode> }
  rootID: EntityID
  hovered: EntityID | null
  setHovered: (id: EntityID | null) => void
  nodeLit: (id: EntityID) => boolean
  edgeLit: (edge: LayoutEdge) => boolean
  showEveryLabel: boolean
  mutedLabels: Set<string>
  onSelect: (ref: EntityRef) => void
}) {
  const vault = useVault()
  const [view, setView] = useState({ x: 0, y: 0, scale: 1 })
  const drag = useRef<{ x: number; y: number } | null>(null)

  // A new subject or a new size is a new picture; keep the old pan and it opens off-screen.
  useEffect(() => setView({ x: 0, y: 0, scale: 1 }), [rootID, size.width, size.height])

  const viewBox = `${view.x} ${view.y} ${size.width / view.scale} ${size.height / view.scale}`

  return (
    <svg
      className="graph"
      viewBox={viewBox}
      width={size.width}
      height={size.height}
      onWheel={(event) => {
        event.preventDefault()
        setView((current) => {
          const scale = clamp(current.scale * Math.exp(-event.deltaY / 400), 0.4, 4)
          // Zoom about the pointer, so the thing under the cursor stays under the cursor.
          const bounds = event.currentTarget.getBoundingClientRect()
          const px = event.clientX - bounds.left
          const py = event.clientY - bounds.top
          return {
            scale,
            x: current.x + px / current.scale - px / scale,
            y: current.y + py / current.scale - py / scale,
          }
        })
      }}
      onMouseDown={(event) => {
        drag.current = { x: event.clientX, y: event.clientY }
      }}
      onMouseMove={(event) => {
        if (!drag.current) return
        const dx = (event.clientX - drag.current.x) / view.scale
        const dy = (event.clientY - drag.current.y) / view.scale
        drag.current = { x: event.clientX, y: event.clientY }
        setView((current) => ({ ...current, x: current.x - dx, y: current.y - dy }))
      }}
      onMouseUp={() => {
        drag.current = null
      }}
      onMouseLeave={() => {
        drag.current = null
        setHovered(null)
      }}
    >
      <g className="edges">
        {layout.edges.map((edge, index) => {
          const from = layout.byID.get(edge.from)
          const to = layout.byID.get(edge.to)
          if (!from || !to) return null
          const lit = edgeLit(edge)
          // Trim along each end's own tangent — towards the control point — so a bowed edge still
          // meets the rim of its circle rather than crossing it.
          const start = towards(from.center, edge.control, from.radius + EDGE_GAP)
          const end = towards(to.center, edge.control, to.radius + EDGE_GAP)
          // Dashed means the relation is written on the *other* person's file. That is not
          // decoration: it says which file to open to change it.
          const inbound = edge.to === rootID
          return (
            <g key={`${edge.from}-${edge.to}-${edge.label}-${index}`} opacity={lit ? 1 : 0.1}>
              <path
                className="edge"
                d={quadPath(start, edge.control, end)}
                strokeDasharray={inbound ? '4 3' : undefined}
              />
              <path className="edge-head" d={arrowhead(end, edge.control)} />
              {(showEveryLabel || (lit && (hovered || mutedLabels.size > 0))) && (
                <text className="edge-label" x={edge.labelPoint.x} y={edge.labelPoint.y}>
                  {edge.label}
                </text>
              )}
            </g>
          )
        })}
      </g>

      <g className="nodes">
        {layout.nodes.map((node) => {
          const candidate = vault.snapshot.people[node.id]
          const isRoot = node.id === rootID
          const hue = clusterColor(node.cluster)
          const lit = nodeLit(node.id)
          return (
            <g
              key={node.id}
              className="node"
              opacity={lit ? 1 : 0.18}
              onMouseEnter={() => setHovered(node.id)}
              onMouseLeave={() => setHovered(null)}
              onClick={() => !isRoot && onSelect({ kind: 'person', id: node.id })}
              style={{ cursor: isRoot ? 'default' : 'pointer' }}
            >
              {/* A generous invisible disc: a 15px circle is a small thing to hit. */}
              <circle
                cx={node.center.x}
                cy={node.center.y}
                r={node.radius + 8}
                fill="transparent"
              />
              {candidate && vault.hasLogo('person', candidate.id) ? (
                <image
                  href={`/assets/people/${encodeURIComponent(node.id)}.png?v=${vault.logoVersion}`}
                  x={node.center.x - node.radius}
                  y={node.center.y - node.radius}
                  width={node.radius * 2}
                  height={node.radius * 2}
                  style={{ clipPath: 'circle(50%)' }}
                  preserveAspectRatio="xMidYMid slice"
                />
              ) : (
                <circle
                  cx={node.center.x}
                  cy={node.center.y}
                  r={node.radius}
                  fill={hue}
                  fillOpacity={candidate?.placeholder ? 0 : 0.9}
                  stroke={hue}
                  strokeWidth={candidate?.placeholder ? 2 : 0}
                  strokeDasharray={candidate?.placeholder ? '4 3' : undefined}
                />
              )}
              <circle
                cx={node.center.x}
                cy={node.center.y}
                r={node.radius}
                fill="none"
                stroke={isRoot ? 'var(--text-normal)' : hue}
                strokeWidth={isRoot ? 2.5 : 1.5}
              />
              <text
                className={`node-label${isRoot ? ' node-label-root' : ''}`}
                x={node.center.x}
                y={node.center.y + node.radius + 14}
              >
                {candidate ? displayName(candidate) : node.id}
              </text>
            </g>
          )
        })}
      </g>
    </svg>
  )
}

// -- helpers -----------------------------------------------------------------------------------

function towards(from: { x: number; y: number }, target: { x: number; y: number }, by: number) {
  if (distance(from, target) === 0) return from
  return trimmed(from, target, by, 0).from
}

function isAdjacent(edges: LayoutEdge[], a: EntityID, b: EntityID): boolean {
  return edges.some(
    (edge) => (edge.from === a && edge.to === b) || (edge.from === b && edge.to === a),
  )
}

function tally(values: string[]): [string, number][] {
  const counts = new Map<string, number>()
  for (const value of values) counts.set(value, (counts.get(value) ?? 0) + 1)
  return [...counts].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
}

function toggled(current: Set<string>, value: string): Set<string> {
  const next = new Set(current)
  if (!next.delete(value)) next.add(value)
  return next
}

function clamp(value: number, low: number, high: number): number {
  return Math.min(high, Math.max(low, value))
}
