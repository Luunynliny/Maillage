// One collapsible section per kind, and the load issues at the bottom.
//
// There is no filter box here on purpose: the palette is the search, and a second one would leave
// two places to type a name into.

import { useState } from 'react'
import type { AnyEntity, EntityKind } from '../../shared/types.ts'
import { ENTITY_KINDS, KIND_PLURAL } from '../../shared/types.ts'
import { DisclosureChevron, Icon, IconButton, SidebarRow } from '../design/components.tsx'
import type { EntityRef } from '../vault/derived.ts'
import { allOrganizations, allPeople, allProjects, sameRef } from '../vault/derived.ts'
import { useVault } from '../vault/store.tsx'

export function Sidebar({
  selection,
  onSelect,
  onNew,
  onEdit,
  onDelete,
  onOpenPalette,
  onPickVault,
}: {
  selection: EntityRef | null
  onSelect: (ref: EntityRef | null) => void
  onNew: (kind: EntityKind, placeholder?: boolean) => void
  onEdit: (ref: EntityRef) => void
  onDelete: (ref: EntityRef) => void
  onOpenPalette: () => void
  onPickVault: () => void
}) {
  const vault = useVault()
  const [collapsed, setCollapsed] = useState<Set<EntityKind>>(new Set())

  const rows: Record<EntityKind, AnyEntity[]> = {
    person: allPeople(vault.snapshot),
    organization: allOrganizations(vault.snapshot),
    project: allProjects(vault.snapshot),
  }

  return (
    <nav className="sidebar">
      {/* The whole band is the way back to the overview, as it was in the native app. */}
      <button className="sidebar-brand" onClick={() => onSelect(null)} type="button">
        maillage
      </button>

      <div className="sidebar-tools">
        <button className="jump-button" onClick={onOpenPalette} type="button">
          <Icon name="search" size={12} />
          <span>Jump to anything</span>
        </button>
        <IconButton icon="reload" label="Reload vault" onClick={() => void vault.reload()} />
      </div>

      <div className="sidebar-sections">
        {ENTITY_KINDS.map((kind) => {
          const open = !collapsed.has(kind)
          return (
            <section key={kind}>
              <div className="sidebar-section-header">
                <button
                  className="sidebar-section-toggle"
                  type="button"
                  onClick={() =>
                    setCollapsed((current) => {
                      const next = new Set(current)
                      if (!next.delete(kind)) next.add(kind)
                      return next
                    })
                  }
                >
                  <DisclosureChevron open={open} />
                  <span className="section-title">{KIND_PLURAL[kind]}</span>
                  <span className="section-count">{rows[kind].length}</span>
                </button>
                {kind === 'person' && (
                  <IconButton
                    icon="person"
                    label="New unnamed person"
                    size={12}
                    onClick={() => onNew('person', true)}
                  />
                )}
                <IconButton
                  icon="plus"
                  label={`New ${kind}`}
                  size={12}
                  onClick={() => onNew(kind)}
                />
              </div>

              {open &&
                rows[kind].map((entity) => (
                  <SidebarRow
                    key={entity.id}
                    entity={entity}
                    hasLogo={vault.hasLogo(kind, entity.id)}
                    selected={sameRef(selection, { kind, id: entity.id })}
                    onClick={() => onSelect({ kind, id: entity.id })}
                    onEdit={() => onEdit({ kind, id: entity.id })}
                    onDelete={() => onDelete({ kind, id: entity.id })}
                  />
                ))}
              {open && !rows[kind].length && (
                <p className="sidebar-empty">No {KIND_PLURAL[kind].toLowerCase()} yet</p>
              )}
            </section>
          )
        })}
      </div>

      {vault.snapshot.issues.length > 0 && (
        <div className="sidebar-issues">
          <span className="section-title">
            {vault.snapshot.issues.length} unreadable{' '}
            {vault.snapshot.issues.length === 1 ? 'file' : 'files'}
          </span>
          {vault.snapshot.issues.slice(0, 3).map((issue) => (
            <p key={issue.path} title={issue.message}>
              <Icon name="warning" size={11} />
              {issue.path}
            </p>
          ))}
        </div>
      )}

      <button className="sidebar-vault" onClick={onPickVault} type="button" title={vault.vaultRoot}>
        {vault.vaultRoot || 'Choose a vault…'}
      </button>
    </nav>
  )
}
