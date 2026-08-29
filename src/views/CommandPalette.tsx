// Type a few letters of anything and go there. This is the app's search — the sidebar
// deliberately has no filter box, so there is only ever one place to type a name.

import { useMemo, useState } from 'react'
import type { AnyEntity } from '../../shared/types.ts'
import { KIND_LABEL, displayName } from '../../shared/types.ts'
import { EntityAvatar, SearchField } from '../design/components.tsx'
import type { EntityRef } from '../vault/derived.ts'
import { allEntities } from '../vault/derived.ts'
import { useVault } from '../vault/store.tsx'
import { fuzzyScore } from './fuzzy.ts'

const LIMIT = 30

export function CommandPalette({
  onSelect,
  onClose,
}: {
  onSelect: (ref: EntityRef) => void
  onClose: () => void
}) {
  const vault = useVault()
  const [query, setQuery] = useState('')
  const [highlighted, setHighlighted] = useState(0)

  const results = useMemo(() => {
    const entities = allEntities(vault.snapshot)
    if (!query.trim()) return entities.slice(0, LIMIT)
    return entities
      .map((entity) => ({ entity, score: bestScore(query.trim(), entity) }))
      .filter((row): row is { entity: AnyEntity; score: number } => row.score !== null)
      .sort(
        (a, b) => b.score - a.score || displayName(a.entity).localeCompare(displayName(b.entity)),
      )
      .slice(0, LIMIT)
      .map((row) => row.entity)
  }, [query, vault.snapshot])

  const choose = (index: number) => {
    const entity = results[index]
    if (entity) onSelect({ kind: entity.kind, id: entity.id })
  }

  return (
    <div
      className="sheet-backdrop"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose()
      }}
    >
      <div className="palette" role="dialog" aria-label="Jump to anything">
        <SearchField
          value={query}
          onChange={(value) => {
            setQuery(value)
            setHighlighted(0)
          }}
          placeholder="Jump to a person, organization or project…"
          autoFocus
          onKeyDown={(event) => {
            if (event.key === 'Escape') onClose()
            if (event.key === 'Enter') choose(highlighted)
            if (event.key === 'ArrowDown') {
              event.preventDefault()
              setHighlighted((current) => Math.min(current + 1, results.length - 1))
            }
            if (event.key === 'ArrowUp') {
              event.preventDefault()
              setHighlighted((current) => Math.max(current - 1, 0))
            }
          }}
        />
        <ul className="palette-results">
          {results.map((entity, index) => (
            <li key={`${entity.kind}/${entity.id}`}>
              <button
                type="button"
                className={`palette-row${index === highlighted ? ' palette-row-on' : ''}`}
                onMouseEnter={() => setHighlighted(index)}
                onClick={() => choose(index)}
              >
                <EntityAvatar
                  kind={entity.kind}
                  id={entity.id}
                  hasLogo={vault.hasLogo(entity.kind, entity.id)}
                  isPlaceholder={entity.kind === 'person' && entity.placeholder}
                  version={vault.logoVersion}
                />
                <span className="palette-name">{displayName(entity)}</span>
                <span className="palette-subtitle">{subtitleOf(entity)}</span>
                <span className="palette-kind">{KIND_LABEL[entity.kind]}</span>
              </button>
            </li>
          ))}
          {!results.length && <li className="palette-empty">Nothing matches that.</li>}
        </ul>
      </div>
    </div>
  )
}

function bestScore(query: string, entity: AnyEntity): number | null {
  const fields = [
    displayName(entity),
    entity.id,
    ...(entity.kind === 'person' ? [entity.role, entity.email] : []),
  ]
  const scores = fields
    .filter((field): field is string => !!field)
    .map((field) => fuzzyScore(query, field))
    .filter((score): score is number => score !== null)
  return scores.length ? Math.max(...scores) : null
}

function subtitleOf(entity: AnyEntity): string {
  if (entity.kind === 'person') return entity.role ?? entity.email ?? entity.descriptor ?? ''
  if (entity.kind === 'organization') return entity.domain ?? ''
  return entity.status
}
