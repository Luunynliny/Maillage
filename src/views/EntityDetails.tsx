// The collapsible fold under the pane header: everything about the subject that is not the
// picture below it. Display-only, except for relations — the one thing you want to add while
// looking at who someone knows.

import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import type { AnyEntity, Organization, Person, Project } from '../../shared/types.ts'
import { KIND_BODY_TITLE, displayName } from '../../shared/types.ts'
import { formatCalendarDay } from '../../shared/calendarDay.ts'
import {
  EntityLink,
  Icon,
  IconButton,
  MetadataList,
  Pill,
  SectionHeader,
} from '../design/components.tsx'
import type { EntityRef } from '../vault/derived.ts'
import {
  membersOfOrganization,
  participantsOfProject,
  projectsInOrganization,
} from '../vault/derived.ts'
import { useVault } from '../vault/store.tsx'
import type { PaneProps } from './CenterPane.tsx'

export function EntityDetails({ entity, ...actions }: PaneProps & { entity: AnyEntity }) {
  return (
    <div className="details">
      {entity.kind === 'person' && <PersonDetails person={entity} {...actions} />}
      {entity.kind === 'organization' && <OrganizationDetails organization={entity} {...actions} />}
      {entity.kind === 'project' && <ProjectDetails project={entity} {...actions} />}
      {entity.body && (
        <section>
          <SectionHeader title={KIND_BODY_TITLE[entity.kind]} />
          <div className="notes">
            <ReactMarkdown remarkPlugins={[remarkGfm]}>{entity.body}</ReactMarkdown>
          </div>
        </section>
      )}
    </div>
  )
}

function PersonDetails({
  person,
  onSelect,
  onAddRelation,
  onResolve,
}: PaneProps & { person: Person }) {
  const vault = useVault()
  const employer = person.organization
    ? vault.snapshot.organizations[person.organization]
    : undefined
  const backlinks = vault.backlinks[person.id] ?? []

  return (
    <>
      <MetadataList
        items={[
          { label: 'Role', value: person.role },
          {
            label: 'Email',
            value: person.email && <a href={`mailto:${person.email}`}>{person.email}</a>,
          },
          { label: 'Added', value: person.created && formatCalendarDay(person.created) },
        ]}
      />

      {person.placeholder && (
        <div className="placeholder-note">
          <span>
            Nobody has put a name to this one yet — {person.descriptor ?? 'an unnamed person'}.
          </span>
          <button
            className="button button-secondary"
            type="button"
            onClick={() => onResolve(person.id)}
          >
            Give them a name
          </button>
        </div>
      )}

      {(employer || person.projects.length > 0) && (
        <section>
          <SectionHeader title="Membership" />
          <div className="pill-cloud">
            {employer && (
              <Pill
                color="var(--organization)"
                onClick={() => onSelect({ kind: 'organization', id: employer.id })}
              >
                {displayName(employer)}
              </Pill>
            )}
            {person.projects.map((membership) => {
              const project = vault.snapshot.projects[membership.to]
              return (
                <Pill
                  key={membership.to}
                  color="var(--project)"
                  onClick={
                    project ? () => onSelect({ kind: 'project', id: project.id }) : undefined
                  }
                >
                  {project ? displayName(project) : membership.to}
                  {membership.role ? ` · ${membership.role}` : ''}
                </Pill>
              )
            })}
          </div>
        </section>
      )}

      <section>
        <SectionHeader
          title="Relations"
          trailing={person.relations.length}
          actions={
            <IconButton
              icon="plus"
              label="Add a relation"
              onClick={() => onAddRelation(person.id)}
            />
          }
        />
        {person.relations.length ? (
          person.relations.map((relation) => {
            const target = vault.snapshot.people[relation.to]
            return (
              <div className="relation-row" key={`${relation.to}|${relation.label}`}>
                <IconButton
                  icon="minus"
                  label={`Remove "${relation.label}"`}
                  size={12}
                  danger
                  onClick={() =>
                    void vault.update({
                      ...person,
                      relations: person.relations.filter(
                        (entry) => entry.to !== relation.to || entry.label !== relation.label,
                      ),
                    })
                  }
                />
                <span className="relation-label">{relation.label}</span>
                <Icon name="arrow" size={12} />
                {target ? (
                  <EntityLink
                    entity={target}
                    hasLogo={vault.hasLogo('person', target.id)}
                    onClick={() => onSelect({ kind: 'person', id: target.id })}
                  />
                ) : (
                  <span className="dangling" title="No file with this id">
                    <Icon name="warning" size={12} /> {relation.to}
                  </span>
                )}
              </div>
            )
          })
        ) : (
          <p className="muted">
            None yet. A relation is written to this person&rsquo;s file only; the other end is
            derived.
          </p>
        )}
      </section>

      {backlinks.length > 0 && (
        <section>
          <SectionHeader title="Referenced by" trailing={backlinks.length} />
          {backlinks.map((backlink) => {
            const source = vault.snapshot.people[backlink.from]
            return (
              <div className="relation-row" key={`${backlink.from}|${backlink.label}`}>
                {source ? (
                  <EntityLink
                    entity={source}
                    hasLogo={vault.hasLogo('person', source.id)}
                    onClick={() => onSelect({ kind: 'person', id: source.id })}
                  />
                ) : (
                  <span className="dangling">{backlink.from}</span>
                )}
                <Icon name="arrow" size={12} />
                <span className="relation-label relation-label-end">{backlink.label}</span>
              </div>
            )
          })}
        </section>
      )}
    </>
  )
}

function OrganizationDetails({
  organization,
  onSelect,
}: PaneProps & { organization: Organization }) {
  const vault = useVault()
  const people = membersOfOrganization(vault.snapshot, organization.id)
  const projects = projectsInOrganization(vault.snapshot, organization.id)

  return (
    <>
      <MetadataList
        items={[
          {
            label: 'Domain',
            value: organization.domain && (
              <a href={`https://${organization.domain}`} target="_blank" rel="noreferrer">
                {organization.domain}
              </a>
            ),
          },
          {
            label: 'Added',
            value: organization.created && formatCalendarDay(organization.created),
          },
        ]}
      />
      <PillSection
        title="People"
        items={people.map((person) => ({
          id: person.id,
          label: displayName(person),
          color: 'var(--person)',
          onClick: () => onSelect({ kind: 'person', id: person.id }),
        }))}
      />
      <PillSection
        title="Projects"
        items={projects.map((project) => ({
          id: project.id,
          label: displayName(project),
          color: 'var(--project)',
          onClick: () => onSelect({ kind: 'project', id: project.id }),
        }))}
      />
    </>
  )
}

function ProjectDetails({ project, onSelect }: PaneProps & { project: Project }) {
  const vault = useVault()
  const owner = project.organization
    ? vault.snapshot.organizations[project.organization]
    : undefined
  const roster = participantsOfProject(vault.snapshot, project.id)

  return (
    <>
      <MetadataList
        items={[
          { label: 'Status', value: project.status },
          { label: 'Added', value: project.created && formatCalendarDay(project.created) },
          {
            label: 'Organization',
            value: owner && (
              <Pill
                color="var(--organization)"
                onClick={() => onSelect({ kind: 'organization', id: owner.id })}
              >
                {displayName(owner)}
              </Pill>
            ),
          },
        ]}
      />
      <PillSection
        title="People"
        items={roster.map(({ person, role }) => ({
          id: person.id,
          label: role ? `${displayName(person)} · ${role}` : displayName(person),
          color: 'var(--person)',
          onClick: () => onSelect({ kind: 'person', id: person.id }),
        }))}
      />
    </>
  )
}

function PillSection({
  title,
  items,
}: {
  title: string
  items: { id: string; label: string; color: string; onClick: () => void }[]
}) {
  if (!items.length) return null
  return (
    <section>
      <SectionHeader title={title} trailing={items.length} />
      <div className="pill-cloud">
        {items.map((item) => (
          <Pill key={item.id} color={item.color} onClick={item.onClick}>
            {item.label}
          </Pill>
        ))}
      </div>
    </section>
  )
}
