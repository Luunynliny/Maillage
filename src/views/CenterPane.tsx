// The centre pane picks its representation from what is selected, because each selection is a
// genuinely different question:
//
//   nothing       → how is the whole network organised by employer?
//   organization  → what is this company working on, and who is on it?
//   person        → who does this person relate to, and who do *they* relate to?
//   project       → who is staffed on this, and in what role?

import { useEffect, useState } from 'react'
import type { AnyEntity } from '../../shared/types.ts'
import { KIND_BODY_TITLE, displayName } from '../../shared/types.ts'
import { DisclosureChevron, EntityAvatar, IconButton } from '../design/components.tsx'
import type { EntityRef } from '../vault/derived.ts'
import {
  membersOfOrganization,
  participantsOfProject,
  projectsInOrganization,
} from '../vault/derived.ts'
import { useVault } from '../vault/store.tsx'
import { EntityDetails } from './EntityDetails.tsx'
import { NetworkGraph } from './NetworkGraph.tsx'
import { OrgBoard, OrgBubbles, ProjectRoster } from './panes.tsx'

export interface PaneProps {
  onSelect: (ref: EntityRef | null) => void
  onEdit: (ref: EntityRef) => void
  onAddRelation: (id: string) => void
  onResolve: (id: string) => void
}

export function CenterPane({ entity, ...actions }: PaneProps & { entity: AnyEntity | undefined }) {
  const [detailsOpen, setDetailsOpen] = useState(false)

  // Details fold shut on every change of subject: what was worth expanding about one person is
  // rarely what is worth expanding about the next.
  useEffect(() => setDetailsOpen(false), [entity?.kind, entity?.id])

  if (!entity) {
    return <OrgBubbles onSelect={actions.onSelect} />
  }

  return (
    <>
      <CenterPaneHeader
        entity={entity}
        open={detailsOpen}
        onToggle={() => setDetailsOpen((open) => !open)}
        onEdit={() => actions.onEdit({ kind: entity.kind, id: entity.id })}
      />
      {detailsOpen && <EntityDetails entity={entity} {...actions} />}
      <div className="pane-body">
        {entity.kind === 'person' && <NetworkGraph person={entity} {...actions} />}
        {entity.kind === 'organization' && <OrgBoard organization={entity} {...actions} />}
        {entity.kind === 'project' && <ProjectRoster project={entity} {...actions} />}
      </div>
    </>
  )
}

function CenterPaneHeader({
  entity,
  open,
  onToggle,
  onEdit,
}: {
  entity: AnyEntity
  open: boolean
  onToggle: () => void
  onEdit: () => void
}) {
  const vault = useVault()
  const unnamed = entity.kind === 'person' && entity.placeholder

  return (
    <header className="pane-header">
      <button className="pane-heading" onClick={onToggle} type="button">
        <EntityAvatar
          kind={entity.kind}
          id={entity.id}
          size={40}
          hasLogo={vault.hasLogo(entity.kind, entity.id)}
          isPlaceholder={unnamed}
          version={vault.logoVersion}
        />
        <span className="pane-heading-text">
          <span className="pane-title">{displayName(entity)}</span>
          <span className="pane-subtitle">{subtitle(entity, vault)}</span>
        </span>
        <DisclosureChevron open={open} />
      </button>
      <IconButton
        icon="pencil"
        label={unnamed ? 'Add a name' : `Edit ${KIND_BODY_TITLE[entity.kind].toLowerCase()}`}
        onClick={onEdit}
      />
    </header>
  )
}

function subtitle(entity: AnyEntity, vault: ReturnType<typeof useVault>): string {
  switch (entity.kind) {
    case 'person': {
      const relations = entity.relations.length
      const referenced = vault.backlinks[entity.id]?.length ?? 0
      return [
        count(relations, 'relation'),
        referenced ? `${count(referenced, 'reference')} in` : '',
        entity.role,
      ]
        .filter(Boolean)
        .join(' · ')
    }
    case 'organization': {
      const people = membersOfOrganization(vault.snapshot, entity.id).length
      const projects = projectsInOrganization(vault.snapshot, entity.id).length
      return [count(people, 'person', 'people'), count(projects, 'project')].join(' · ')
    }
    case 'project': {
      const participants = participantsOfProject(vault.snapshot, entity.id)
      const unassigned = participants.filter((entry) => !entry.role).length
      return [
        count(participants.length, 'participant'),
        entity.status,
        unassigned ? `${unassigned} without a role` : '',
      ]
        .filter(Boolean)
        .join(' · ')
    }
  }
}

function count(n: number, singular: string, plural = `${singular}s`): string {
  return `${n} ${n === 1 ? singular : plural}`
}
