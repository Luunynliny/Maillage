// The vault's data model. Imported by both the server (which reads and writes the files) and the
// client (which renders them), so it holds no I/O and no React.
//
// Every entity's `id` is its filename stem and the only link target; see `server/vault.ts`, which
// overwrites whatever `id:` the frontmatter claims with the actual filename.

export type EntityID = string

export type EntityKind = 'person' | 'organization' | 'project'

export const ENTITY_KINDS = ['person', 'organization', 'project'] as const

/** Vault subdirectory per kind. Also the `assets/<dir>/` partition for logos. */
export const KIND_DIRECTORY: Record<EntityKind, string> = {
  person: 'people',
  organization: 'organizations',
  project: 'projects',
}

export const KIND_LABEL: Record<EntityKind, string> = {
  person: 'Person',
  organization: 'Organization',
  project: 'Project',
}

export const KIND_PLURAL: Record<EntityKind, string> = {
  person: 'People',
  organization: 'Organizations',
  project: 'Projects',
}

/**
 * A date with no time and no zone, as `YYYY-MM-DD`.
 *
 * A plain string rather than a Date on purpose: a Date is a UTC instant, and serializing one
 * shifts the calendar day backward for anyone east of UTC. String compare is also the correct
 * chronological compare for this format.
 */
export type CalendarDay = string

/** A labeled edge, stored only on the source person's file. Never write the inverse. */
export interface Relation {
  to: EntityID
  label: string
}

/** The in-memory inverse of a `Relation`. Derived at load, never persisted. */
export interface Backlink {
  from: EntityID
  label: string
}

/** A person's membership of a project, with the role they play on it. */
export interface ProjectMembership {
  to: EntityID
  role?: string
}

export interface Person {
  kind: 'person'
  id: EntityID
  firstname?: string
  lastname?: string
  email?: string
  /** Free-text job title. */
  role?: string
  /** True for "you should meet the head of AA" — no name yet, an `_`-prefixed id. */
  placeholder: boolean
  /** What an unnamed person is known by until they get a name. */
  descriptor?: string
  /** Singular: the People graph clusters on employer and a cluster needs one key per node. */
  organization?: EntityID
  projects: ProjectMembership[]
  relations: Relation[]
  created?: CalendarDay
  body: string
}

export interface Organization {
  kind: 'organization'
  id: EntityID
  name: string
  domain?: string
  created?: CalendarDay
  body: string
}

export type ProjectStatus = 'active' | 'paused' | 'done'

export const PROJECT_STATUSES = ['active', 'paused', 'done'] as const

export interface Project {
  kind: 'project'
  id: EntityID
  name: string
  status: ProjectStatus
  /** Singular: a project belongs to whoever owns the work, so boards partition rather than overlap. */
  organization?: EntityID
  created?: CalendarDay
  body: string
}

export type AnyEntity = Person | Organization | Project

/** A file that would not parse. One bad file never takes down the vault. */
export interface VaultLoadIssue {
  path: string
  message: string
}

export interface VaultSnapshot {
  people: Record<EntityID, Person>
  organizations: Record<EntityID, Organization>
  projects: Record<EntityID, Project>
  /** Derived by scanning `assets/`: a logo's presence on disk *is* the fact. */
  logoIDs: Record<EntityKind, EntityID[]>
  issues: VaultLoadIssue[]
}

export function displayName(entity: AnyEntity): string {
  if (entity.kind !== 'person') return entity.name || entity.id
  const name = [entity.firstname, entity.lastname].filter(Boolean).join(' ').trim()
  return name || entity.descriptor || entity.id
}

/** The free-markdown section's heading, per kind. */
export const KIND_BODY_TITLE: Record<EntityKind, string> = {
  person: 'Notes',
  organization: 'Notes',
  project: 'Description',
}
