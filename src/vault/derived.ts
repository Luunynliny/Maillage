// Everything the views read that is not stored on disk.
//
// Membership and relations live on exactly one side of a link, and the other side's view of them
// is always computed here — never written back. That is what keeps `people/marie-dupont.md` the
// single place a fact about Marie lives.

import type {
  AnyEntity,
  Backlink,
  EntityID,
  EntityKind,
  Organization,
  Person,
  Project,
  VaultSnapshot,
} from '../../shared/types.ts'
import { displayName } from '../../shared/types.ts'

/** What the sidebar, the palette and the graph all point at. Kind included: ids only collide
 * across kinds, so `people/acme.md` and `projects/acme.md` can both exist. */
export interface EntityRef {
  kind: EntityKind
  id: EntityID
}

export function sameRef(a: EntityRef | null, b: EntityRef | null): boolean {
  return a?.kind === b?.kind && a?.id === b?.id
}

const byName = (a: AnyEntity, b: AnyEntity) => displayName(a).localeCompare(displayName(b))

export function allPeople(snapshot: VaultSnapshot): Person[] {
  return Object.values(snapshot.people).sort(byName)
}

export function allOrganizations(snapshot: VaultSnapshot): Organization[] {
  return Object.values(snapshot.organizations).sort(byName)
}

export function allProjects(snapshot: VaultSnapshot): Project[] {
  return Object.values(snapshot.projects).sort(byName)
}

export function allEntities(snapshot: VaultSnapshot): AnyEntity[] {
  return [...allPeople(snapshot), ...allOrganizations(snapshot), ...allProjects(snapshot)]
}

export function lookup(snapshot: VaultSnapshot, ref: EntityRef | null): AnyEntity | undefined {
  if (!ref) return undefined
  switch (ref.kind) {
    case 'person':
      return snapshot.people[ref.id]
    case 'organization':
      return snapshot.organizations[ref.id]
    case 'project':
      return snapshot.projects[ref.id]
  }
}

/** The display name for a link target, falling back to the raw id when it dangles. */
export function nameOf(snapshot: VaultSnapshot, kind: EntityKind, id: EntityID): string {
  const entity = lookup(snapshot, { kind, id })
  return entity ? displayName(entity) : id
}

export function exists(snapshot: VaultSnapshot, kind: EntityKind, id: EntityID): boolean {
  return lookup(snapshot, { kind, id }) !== undefined
}

// -- backlinks --------------------------------------------------------------------------------

export type BacklinkIndex = Record<EntityID, Backlink[]>

/**
 * Invert every person's relations. A relation is written only to the source person's file; this is
 * what lets the target show "Referenced by" without an inverse edge ever existing on disk.
 */
export function buildBacklinks(snapshot: VaultSnapshot): BacklinkIndex {
  const index: BacklinkIndex = {}
  for (const person of Object.values(snapshot.people)) {
    for (const relation of person.relations) {
      ;(index[relation.to] ??= []).push({ from: person.id, label: relation.label })
    }
  }
  for (const backlinks of Object.values(index)) {
    backlinks.sort(
      (a, b) =>
        nameOf(snapshot, 'person', a.from).localeCompare(nameOf(snapshot, 'person', b.from)) ||
        a.label.localeCompare(b.label),
    )
  }
  return index
}

// -- membership -------------------------------------------------------------------------------

export function membersOfOrganization(snapshot: VaultSnapshot, id: EntityID): Person[] {
  return allPeople(snapshot).filter((person) => person.organization === id)
}

export interface Participant {
  person: Person
  role?: string
}

/** A project's roster, read by scanning people — the project file holds no member list. */
export function participantsOfProject(snapshot: VaultSnapshot, id: EntityID): Participant[] {
  const participants: Participant[] = []
  for (const person of allPeople(snapshot)) {
    const membership = person.projects.find((entry) => entry.to === id)
    if (membership) participants.push({ person, role: membership.role })
  }
  return participants
}

export function projectsInOrganization(snapshot: VaultSnapshot, id: EntityID): Project[] {
  return allProjects(snapshot).filter((project) => project.organization === id)
}

export function projectsOf(snapshot: VaultSnapshot, person: Person): Project[] {
  return person.projects
    .map((entry) => snapshot.projects[entry.to])
    .filter((project): project is Project => project !== undefined)
}

export interface OrganizationGroup {
  organization?: Organization
  people: Person[]
}

/**
 * People bucketed by employer, alphabetically, with the unaffiliated always last.
 *
 * This ordering is load-bearing beyond the bubbles view: a group's index here is its cluster
 * colour everywhere, so a person's hue has to mean the same thing in the network graph as in the
 * bubbles. An employer nobody works for is omitted rather than drawn as an empty circle, and a
 * person whose employer link dangles falls into the unaffiliated bucket rather than vanishing.
 */
export function peopleGroupedByOrganization(snapshot: VaultSnapshot): OrganizationGroup[] {
  const groups: OrganizationGroup[] = []
  for (const organization of allOrganizations(snapshot)) {
    const people = membersOfOrganization(snapshot, organization.id)
    if (people.length) groups.push({ organization, people })
  }
  const unaffiliated = allPeople(snapshot).filter(
    (person) => !person.organization || !snapshot.organizations[person.organization],
  )
  if (unaffiliated.length) groups.push({ people: unaffiliated })
  return groups
}

/** The index into the cluster palette for a person's employer, or null when they have none. */
export function clusterIndexOf(groups: OrganizationGroup[], person: Person): number | null {
  const index = groups.findIndex((group) => group.organization?.id === person.organization)
  return index === -1 || !groups[index]?.organization ? null : index
}

// -- vocabulary -------------------------------------------------------------------------------

/** Whatever is already in the vault, most-used first. There is no tag registry and no config. */
export function usedRelationLabels(snapshot: VaultSnapshot): string[] {
  return byFrequency(
    Object.values(snapshot.people).flatMap((person) =>
      person.relations.map((relation) => relation.label),
    ),
  )
}

export function usedProjectRoles(snapshot: VaultSnapshot): string[] {
  return byFrequency(
    Object.values(snapshot.people).flatMap((person) =>
      person.projects.map((entry) => entry.role).filter((role): role is string => !!role),
    ),
  )
}

function byFrequency(values: string[]): string[] {
  const counts = new Map<string, number>()
  for (const value of values) {
    const trimmed = value.trim()
    if (trimmed) counts.set(trimmed, (counts.get(trimmed) ?? 0) + 1)
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([value]) => value)
}
