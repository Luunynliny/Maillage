// The three panes that are not the network graph. All laid out from a stack or a computed
// packing; none of them simulates anything.

import { useMemo } from 'react'
import type { Organization, Project } from '../../shared/types.ts'
import { displayName } from '../../shared/types.ts'
import { Card, EmptyState, EntityAvatar, EntityLink, Icon } from '../design/components.tsx'
import { packBubbles } from '../graph/bubblePacking.ts'
import type { EntityRef } from '../vault/derived.ts'
import {
  membersOfOrganization,
  participantsOfProject,
  projectsInOrganization,
} from '../vault/derived.ts'
import { useVault } from '../vault/store.tsx'
import { useElementSize } from './useElementSize.ts'

export function clusterColor(index: number | null): string {
  return index === null ? 'var(--cluster-none)' : `var(--cluster-${index % 7})`
}

// -- the overview ----------------------------------------------------------------------------

/**
 * One circle per employer, area proportional to headcount. This is what "nothing selected" means:
 * the shape of the whole network before you have asked about anyone in particular.
 */
export function OrgBubbles({ onSelect }: { onSelect: (ref: EntityRef | null) => void }) {
  const vault = useVault()
  const [ref, size] = useElementSize()

  const bubbles = useMemo(
    () =>
      size.width
        ? packBubbles(
            vault.groups.map((group) => ({
              id: group.organization?.id ?? null,
              label: group.organization ? displayName(group.organization) : 'No employer',
              headcount: group.people.length,
            })),
            size,
          )
        : [],
    [vault.groups, size],
  )

  return (
    <div className="pane-body bubbles" ref={ref}>
      {!vault.groups.length ? (
        <EmptyState
          icon="organization"
          title="Nothing in the vault yet"
          message="Add a person, an organization or a project from the sidebar, and this becomes a map of who works where."
        />
      ) : (
        bubbles.map((bubble, index) => {
          const hue = clusterColor(bubble.id ? index : null)
          return (
            <button
              key={bubble.id ?? '__none__'}
              className="bubble"
              type="button"
              disabled={!bubble.id}
              onClick={() => bubble.id && onSelect({ kind: 'organization', id: bubble.id })}
              style={{
                left: bubble.center.x - bubble.radius,
                top: bubble.center.y - bubble.radius,
                width: bubble.radius * 2,
                height: bubble.radius * 2,
                color: hue,
              }}
            >
              {bubble.id && (
                <EntityAvatar
                  kind="organization"
                  id={bubble.id}
                  size={Math.max(16, bubble.radius * 0.5)}
                  hasLogo={vault.hasLogo('organization', bubble.id)}
                  tint={hue}
                  version={vault.logoVersion}
                />
              )}
              <span className="bubble-count">{bubble.headcount}</span>
              <span className="bubble-label">{bubble.label}</span>
            </button>
          )
        })
      )}
    </div>
  )
}

// -- an organization -------------------------------------------------------------------------

/** A card per project, listing who staffs it, plus everyone the company employs on nothing. */
export function OrgBoard({
  organization,
  onSelect,
}: {
  organization: Organization
  onSelect: (ref: EntityRef | null) => void
}) {
  const vault = useVault()
  const projects = projectsInOrganization(vault.snapshot, organization.id)
  const employees = membersOfOrganization(vault.snapshot, organization.id)
  const staffed = new Set(
    projects.flatMap((project) =>
      participantsOfProject(vault.snapshot, project.id).map((entry) => entry.person.id),
    ),
  )
  const idle = employees.filter((person) => !staffed.has(person.id))

  if (!projects.length && !employees.length) {
    return (
      <EmptyState
        icon="project"
        title={`Nothing on ${displayName(organization)} yet`}
        message="Give someone this employer, or give a project this owner, and its board fills in."
      />
    )
  }

  return (
    <div className="board">
      {projects.map((project) => {
        const roster = participantsOfProject(vault.snapshot, project.id)
        return (
          <Card key={project.id} className="board-card">
            <button
              className="board-card-head"
              type="button"
              onClick={() => onSelect({ kind: 'project', id: project.id })}
            >
              <EntityAvatar
                kind="project"
                id={project.id}
                size={34}
                hasLogo={vault.hasLogo('project', project.id)}
                version={vault.logoVersion}
              />
              <span>
                <span className="board-card-name">{displayName(project)}</span>
                <span className="board-card-status">{project.status}</span>
              </span>
            </button>
            {roster.length ? (
              roster.map(({ person, role }) => (
                <div className="board-member" key={person.id}>
                  <EntityLink
                    entity={person}
                    size={26}
                    hasLogo={vault.hasLogo('person', person.id)}
                    onClick={() => onSelect({ kind: 'person', id: person.id })}
                    suffix={
                      person.organization !== organization.id ? (
                        <span className="board-outsider" title="Works elsewhere">
                          <Icon name="arrow" size={11} />
                        </span>
                      ) : undefined
                    }
                  />
                  {role && <span className="board-role">{role}</span>}
                </div>
              ))
            ) : (
              <p className="board-empty">Nobody staffed</p>
            )}
          </Card>
        )
      })}

      {idle.length > 0 && (
        <Card className="board-card board-card-idle">
          <div className="board-card-head">
            <span className="board-card-name">On no project</span>
          </div>
          {idle.map((person) => (
            <div className="board-member" key={person.id}>
              <EntityLink
                entity={person}
                size={26}
                hasLogo={vault.hasLogo('person', person.id)}
                onClick={() => onSelect({ kind: 'person', id: person.id })}
              />
            </div>
          ))}
        </Card>
      )}
    </div>
  )
}

// -- a project -------------------------------------------------------------------------------

/** Who is on it, and in what role. A table, because that is the question in the plural. */
export function ProjectRoster({
  project,
  onSelect,
}: {
  project: Project
  onSelect: (ref: EntityRef | null) => void
}) {
  const vault = useVault()
  const roster = participantsOfProject(vault.snapshot, project.id)

  if (!roster.length) {
    return (
      <EmptyState
        icon="person"
        title="Nobody on this project yet"
        message="Staffing is edited in the project editor, so an abandoned sheet writes nothing."
      />
    )
  }

  return (
    <table className="roster">
      <thead>
        <tr>
          <th>Participant</th>
          <th>Role</th>
          <th>Organization</th>
        </tr>
      </thead>
      <tbody>
        {roster.map(({ person, role }) => {
          const employer = person.organization
            ? vault.snapshot.organizations[person.organization]
            : undefined
          return (
            <tr key={person.id}>
              <td>
                <EntityLink
                  entity={person}
                  size={28}
                  hasLogo={vault.hasLogo('person', person.id)}
                  onClick={() => onSelect({ kind: 'person', id: person.id })}
                />
              </td>
              <td>{role ?? <span className="muted">—</span>}</td>
              <td>
                {employer ? (
                  <EntityLink
                    entity={employer}
                    size={20}
                    hasLogo={vault.hasLogo('organization', employer.id)}
                    onClick={() => onSelect({ kind: 'organization', id: employer.id })}
                  />
                ) : (
                  <span className="muted">—</span>
                )}
              </td>
            </tr>
          )
        })}
      </tbody>
    </table>
  )
}
