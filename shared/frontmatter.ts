// The whole `---\nyaml\n---\nbody` file format, in one place.
//
// The hard requirement here is byte-for-byte round-tripping, because a vault is a git
// repository. If opening a person and saving them unchanged rewrote quoting, key
// order or list indentation, every save would produce a diff nobody asked for. `frontmatter.test.ts`
// gates that against real vault files; treat a failure there as "the codec is not done".

import { Document, Scalar, visit, parse as parseYAML } from 'yaml'
import { toCalendarDay } from './calendarDay.ts'
import type {
  AnyEntity,
  EntityID,
  EntityKind,
  Organization,
  Person,
  Project,
  ProjectMembership,
  ProjectStatus,
  Relation,
} from './types.ts'
import { PROJECT_STATUSES } from './types.ts'
import { formatWikilink, isWikilink, parseWikilink } from './wikilink.ts'

const FENCE = /^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/
const DAY = /^\d{4}-\d{2}-\d{2}$/

export class FrontmatterError extends Error {}

export interface SplitFile {
  yaml: string
  body: string
}

/**
 * Split a file into its YAML half and its markdown half. The body comes back trimmed, because
 * `encode` always writes exactly one blank line after the closing fence and one newline at the end
 * — the shape existing vault files already have, so they round-trip unchanged.
 */
export function splitFrontmatter(text: string): SplitFile {
  const match = FENCE.exec(text)
  if (!match) throw new FrontmatterError('no YAML frontmatter (a file must start with `---`)')
  return { yaml: match[1]!, body: text.slice(match[0].length).trim() }
}

export function joinFrontmatter(yaml: string, body: string): string {
  const fenced = `---\n${yaml.endsWith('\n') ? yaml : `${yaml}\n`}---\n`
  return body ? `${fenced}\n${body}\n` : fenced
}

// -- decoding ---------------------------------------------------------------------------------

/**
 * Decode one vault file. `id` is the filename stem and wins over any `id:` in the frontmatter —
 * the filename is the identity, and a link target that disagreed with its own filename would be
 * unreachable.
 */
export function decodeEntity(kind: EntityKind, id: EntityID, text: string): AnyEntity {
  const { yaml, body } = splitFrontmatter(text)
  let raw: unknown
  try {
    raw = parseYAML(yaml)
  } catch (error) {
    throw new FrontmatterError(error instanceof Error ? error.message : String(error))
  }
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new FrontmatterError('frontmatter is not a mapping')
  }
  const fields = raw as Record<string, unknown>
  switch (kind) {
    case 'person':
      return decodePerson(id, fields, body)
    case 'organization':
      return decodeOrganization(id, fields, body)
    case 'project':
      return decodeProject(id, fields, body)
  }
}

function decodePerson(id: EntityID, fields: Record<string, unknown>, body: string): Person {
  return {
    kind: 'person',
    id,
    firstname: text(fields.firstname),
    lastname: text(fields.lastname),
    email: text(fields.email),
    role: text(fields.role),
    placeholder: fields.placeholder === true,
    descriptor: text(fields.descriptor),
    organization: singularOrganization(fields),
    projects: decodeMemberships(fields.projects),
    relations: decodeRelations(fields.relations),
    created: toCalendarDay(fields.created),
    body,
  }
}

function decodeOrganization(
  id: EntityID,
  fields: Record<string, unknown>,
  body: string,
): Organization {
  return {
    kind: 'organization',
    id,
    name: text(fields.name) ?? id,
    domain: text(fields.domain),
    created: toCalendarDay(fields.created),
    body,
  }
}

function decodeProject(id: EntityID, fields: Record<string, unknown>, body: string): Project {
  const status = text(fields.status)
  return {
    kind: 'project',
    id,
    name: text(fields.name) ?? id,
    status: PROJECT_STATUSES.includes(status as ProjectStatus)
      ? (status as ProjectStatus)
      : 'active',
    organization: singularOrganization(fields),
    created: toCalendarDay(fields.created),
    body,
  }
}

/**
 * `organization:` is singular on both people and projects. The retired plural `organizations:`
 * still decodes so old vaults load — first entry wins, the rest are dropped — but only the
 * singular form is ever written, so a file migrates forward the next time it is saved.
 */
function singularOrganization(fields: Record<string, unknown>): EntityID | undefined {
  const single = link(fields.organization)
  if (single) return single
  const plural = fields.organizations
  return Array.isArray(plural) ? link(plural[0]) : undefined
}

function decodeRelations(value: unknown): Relation[] {
  if (!Array.isArray(value)) return []
  const relations: Relation[] = []
  for (const entry of value) {
    if (entry === null || typeof entry !== 'object') continue
    const to = link((entry as Record<string, unknown>).to)
    const label = text((entry as Record<string, unknown>).label)
    if (to && label) relations.push({ to, label })
  }
  return relations
}

/** An entry is a bare `"[[id]]"` until a role is set, then a `to:`/`role:` mapping. Accept both. */
function decodeMemberships(value: unknown): ProjectMembership[] {
  if (!Array.isArray(value)) return []
  const memberships: ProjectMembership[] = []
  for (const entry of value) {
    if (typeof entry === 'string') {
      const to = link(entry)
      if (to) memberships.push({ to })
      continue
    }
    if (entry === null || typeof entry !== 'object') continue
    const to = link((entry as Record<string, unknown>).to)
    if (!to) continue
    const role = text((entry as Record<string, unknown>).role)
    memberships.push(role ? { to, role } : { to })
  }
  return memberships
}

function text(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined
  const trimmed = value.trim()
  return trimmed ? trimmed : undefined
}

function link(value: unknown): EntityID | undefined {
  const raw = text(value)
  if (!raw) return undefined
  const id = parseWikilink(raw)
  return id || undefined
}

// -- encoding ---------------------------------------------------------------------------------

/** Serialize an entity back to a full file. Key order below is the on-disk key order. */
export function encodeEntity(entity: AnyEntity): string {
  return joinFrontmatter(stringifyFrontmatter(frontmatterOf(entity)), entity.body)
}

function frontmatterOf(entity: AnyEntity): Record<string, unknown> {
  switch (entity.kind) {
    case 'person':
      return omitEmpty({
        id: entity.id,
        type: 'person',
        firstname: entity.firstname,
        lastname: entity.lastname,
        email: entity.email,
        role: entity.role,
        // Always written, even when false: it is what tells a nameless row from an unfilled one.
        placeholder: entity.placeholder,
        descriptor: entity.descriptor,
        organization: entity.organization && formatWikilink(entity.organization),
        projects: entity.projects.length ? entity.projects.map(encodeMembership) : undefined,
        relations: entity.relations.length ? entity.relations.map(encodeRelation) : undefined,
        created: entity.created,
      })
    case 'organization':
      return omitEmpty({
        id: entity.id,
        type: 'organization',
        name: entity.name,
        domain: entity.domain,
        created: entity.created,
      })
    case 'project':
      return omitEmpty({
        id: entity.id,
        type: 'project',
        name: entity.name,
        status: entity.status,
        organization: entity.organization && formatWikilink(entity.organization),
        created: entity.created,
      })
  }
}

/** Collapses back to the bare `"[[id]]"` whenever the role is empty, so an untouched entry stays
 * byte-identical across saves and adding a role is the only thing that expands a file's YAML. */
function encodeMembership(membership: ProjectMembership): string | Record<string, unknown> {
  const role = membership.role?.trim()
  return role ? { to: formatWikilink(membership.to), role } : formatWikilink(membership.to)
}

function encodeRelation(relation: Relation): Record<string, unknown> {
  return { to: formatWikilink(relation.to), label: relation.label }
}

function omitEmpty(fields: Record<string, unknown>): Record<string, unknown> {
  const kept: Record<string, unknown> = {}
  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined || value === null) continue
    if (typeof value === 'string' && !value.trim()) continue
    kept[key] = value
  }
  return kept
}

/**
 * `indentSeq: false` and `lineWidth: 0` match the files already on disk: sequences flush with their key,
 * and a long list of wikilinks is never folded mid-array.
 *
 * The explicit quoting pass is the part that would otherwise drift. A wikilink has to be quoted
 * (it opens with `[`) and yaml would reach for double quotes; a `YYYY-MM-DD` day needs no quotes
 * at all under YAML 1.2 and yaml would emit it bare — but a bare date is a timestamp to any reader
 * still on YAML 1.1, which is exactly the ambiguity `CalendarDay` exists to avoid. Both are pinned
 * to single quotes here rather than left to a heuristic.
 */
function stringifyFrontmatter(fields: Record<string, unknown>): string {
  const doc = new Document(fields)
  visit(doc, {
    Scalar(_key, node) {
      if (typeof node.value !== 'string') return
      if (isWikilink(node.value) || DAY.test(node.value)) node.type = Scalar.QUOTE_SINGLE
    },
  })
  return doc.toString({ lineWidth: 0, indentSeq: false, singleQuote: true })
}
