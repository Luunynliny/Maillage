// The vault on disk: reading it, and every mutation that touches it.
//
// This is the only module in the app that calls the filesystem. It owns the operations that span
// more than one file — rename, delete, roster diffs — because those have to leave the vault
// consistent, and a client doing them over several requests could be interrupted halfway.

import { randomUUID } from 'node:crypto'
import { constants } from 'node:fs'
import { access, mkdir, readFile, readdir, rename, rm, unlink, writeFile } from 'node:fs/promises'
import { basename, dirname, join } from 'node:path'
import { decodeEntity, encodeEntity } from '../shared/frontmatter.ts'
import type {
  AnyEntity,
  EntityID,
  EntityKind,
  Person,
  Project,
  ProjectMembership,
  VaultLoadIssue,
  VaultSnapshot,
} from '../shared/types.ts'
import { ENTITY_KINDS, KIND_DIRECTORY } from '../shared/types.ts'

export class VaultError extends Error {}

// -- paths ------------------------------------------------------------------------------------

export function entityDir(root: string, kind: EntityKind): string {
  return join(root, KIND_DIRECTORY[kind])
}

export function entityPath(root: string, kind: EntityKind, id: EntityID): string {
  return join(entityDir(root, kind), `${id}.md`)
}

/**
 * A logo is a file, not a field: `assets/<kind>/<id>.png`, and its presence *is* the fact.
 * Partitioned by kind because ids only collide across kinds — `people/acme.md` and
 * `projects/acme.md` can coexist.
 */
export function logoPath(root: string, kind: EntityKind, id: EntityID): string {
  return join(root, 'assets', KIND_DIRECTORY[kind], `${id}.png`)
}

/**
 * The one guard between a request and the filesystem. Ids reach the server from the client, so a
 * separator or a `..` here would be a path traversal out of the vault.
 */
export function assertSafeID(id: string): EntityID {
  const trimmed = id.trim()
  const unsafe =
    !trimmed ||
    trimmed === '.' ||
    trimmed === '..' ||
    trimmed.includes('/') ||
    trimmed.includes('\\') ||
    trimmed.includes('\0')
  if (unsafe) throw new VaultError(`unusable id: ${JSON.stringify(id)}`)
  return trimmed
}

export function isEntityKind(value: string): value is EntityKind {
  return (ENTITY_KINDS as readonly string[]).includes(value)
}

// -- atomic writing ---------------------------------------------------------------------------

/**
 * Write via a same-directory temp file, then `rename` it into place — atomic on every filesystem
 * we care about. A crash mid-save can leave the destination wholly old or wholly new, never half
 * written. Every write in this module goes through here, logos included.
 */
async function writeAtomically(path: string, data: string | Uint8Array): Promise<void> {
  await mkdir(dirname(path), { recursive: true })
  const temp = join(dirname(path), `.${basename(path)}.tmp-${randomUUID()}`)
  try {
    await writeFile(temp, data)
    await rename(temp, path)
  } catch (error) {
    await rm(temp, { force: true })
    throw error
  }
}

async function exists(path: string): Promise<boolean> {
  try {
    await access(path, constants.F_OK)
    return true
  } catch {
    return false
  }
}

// -- reading ----------------------------------------------------------------------------------

export async function ensureSkeleton(root: string): Promise<void> {
  for (const kind of ENTITY_KINDS) {
    await mkdir(entityDir(root, kind), { recursive: true })
    await mkdir(join(root, 'assets', KIND_DIRECTORY[kind]), { recursive: true })
  }
}

/**
 * Read the whole vault. A file that will not parse becomes a `VaultLoadIssue` and everything else
 * still loads: one bad file never takes down the vault.
 */
export async function readVault(root: string): Promise<VaultSnapshot> {
  const snapshot: VaultSnapshot = {
    people: {},
    organizations: {},
    projects: {},
    logoIDs: { person: [], organization: [], project: [] },
    issues: [],
  }

  for (const kind of ENTITY_KINDS) {
    for (const file of await markdownFiles(entityDir(root, kind))) {
      const id = file.slice(0, -'.md'.length)
      const relative = `${KIND_DIRECTORY[kind]}/${file}`
      try {
        const entity = decodeEntity(
          kind,
          id,
          await readFile(join(entityDir(root, kind), file), 'utf8'),
        )
        put(snapshot, entity)
      } catch (error) {
        snapshot.issues.push({
          path: relative,
          message: error instanceof Error ? error.message : String(error),
        })
      }
    }
    snapshot.logoIDs[kind] = await logoIDs(root, kind)
  }

  snapshot.issues.sort((a, b) => a.path.localeCompare(b.path))
  return snapshot
}

async function markdownFiles(dir: string): Promise<string[]> {
  let entries: string[]
  try {
    entries = await readdir(dir)
  } catch {
    return []
  }
  // A leading dot is either an interrupted atomic write or something else's business.
  return entries.filter((name) => name.endsWith('.md') && !name.startsWith('.')).sort()
}

async function logoIDs(root: string, kind: EntityKind): Promise<EntityID[]> {
  try {
    const entries = await readdir(join(root, 'assets', KIND_DIRECTORY[kind]))
    return entries
      .filter((name) => name.endsWith('.png') && !name.startsWith('.'))
      .map((name) => name.slice(0, -'.png'.length))
      .sort()
  } catch {
    return []
  }
}

function put(snapshot: VaultSnapshot, entity: AnyEntity): void {
  switch (entity.kind) {
    case 'person':
      snapshot.people[entity.id] = entity
      break
    case 'organization':
      snapshot.organizations[entity.id] = entity
      break
    case 'project':
      snapshot.projects[entity.id] = entity
      break
  }
}

// -- writing ----------------------------------------------------------------------------------

export async function writeEntity(root: string, entity: AnyEntity): Promise<AnyEntity> {
  assertSafeID(entity.id)
  await writeAtomically(entityPath(root, entity.kind, entity.id), encodeEntity(entity))
  return entity
}

/**
 * The first free id at or after `base`: `acme-corp`, then `acme-corp-2`, `acme-corp-3`. Only the
 * kind's own directory is checked, since ids only need to be unique within a kind.
 */
export async function availableID(root: string, kind: EntityKind, base: string): Promise<EntityID> {
  const stem = assertSafeID(base)
  if (!(await exists(entityPath(root, kind, stem)))) return stem
  for (let suffix = 2; ; suffix += 1) {
    const candidate = `${stem}-${suffix}`
    if (!(await exists(entityPath(root, kind, candidate)))) return candidate
  }
}

export async function createEntity(root: string, entity: AnyEntity): Promise<AnyEntity> {
  const id = await availableID(root, entity.kind, entity.id)
  return writeEntity(root, { ...entity, id })
}

/**
 * Delete an entity, then scrub every reference to it. No soft delete, no tombstone: a link that
 * pointed at a file that is gone would render as a dangling name forever.
 */
export async function deleteEntity(root: string, kind: EntityKind, id: EntityID): Promise<void> {
  assertSafeID(id)
  await rm(entityPath(root, kind, id), { force: true })
  await rm(logoPath(root, kind, id), { force: true })

  const snapshot = await readVault(root)
  for (const person of Object.values(snapshot.people)) {
    const scrubbed: Person = {
      ...person,
      organization:
        kind === 'organization' && person.organization === id ? undefined : person.organization,
      projects:
        kind === 'project' ? person.projects.filter((entry) => entry.to !== id) : person.projects,
      relations:
        kind === 'person' ? person.relations.filter((entry) => entry.to !== id) : person.relations,
    }
    if (changed(person, scrubbed)) await writeEntity(root, scrubbed)
  }
  if (kind === 'organization') {
    for (const project of Object.values(snapshot.projects)) {
      if (project.organization === id)
        await writeEntity(root, { ...project, organization: undefined })
    }
  }
}

/**
 * Rename, repairing every inbound reference as it goes. This is the one operation that has to
 * touch files other than its own, because `id` is the only link target there is.
 */
export async function renameEntity(
  root: string,
  kind: EntityKind,
  from: EntityID,
  to: EntityID,
): Promise<EntityID> {
  assertSafeID(from)
  const target = assertSafeID(to)
  if (target === from) return from
  if (!(await exists(entityPath(root, kind, from)))) {
    throw new VaultError(`no ${kind} with id ${from}`)
  }
  if (await exists(entityPath(root, kind, target))) {
    throw new VaultError(`a ${kind} named ${target} already exists`)
  }

  const moved = decodeEntity(kind, from, await readFile(entityPath(root, kind, from), 'utf8'))
  moved.id = target
  await writeEntity(root, moved)
  await rm(entityPath(root, kind, from), { force: true })

  if (await exists(logoPath(root, kind, from))) {
    await mkdir(dirname(logoPath(root, kind, target)), { recursive: true })
    await rename(logoPath(root, kind, from), logoPath(root, kind, target))
  }

  await repoint(root, kind, from, target)
  return target
}

async function repoint(
  root: string,
  kind: EntityKind,
  from: EntityID,
  to: EntityID,
): Promise<void> {
  const snapshot = await readVault(root)
  for (const person of Object.values(snapshot.people)) {
    const repointed: Person = {
      ...person,
      organization:
        kind === 'organization' && person.organization === from ? to : person.organization,
      projects:
        kind === 'project'
          ? person.projects.map((entry) => (entry.to === from ? { ...entry, to } : entry))
          : person.projects,
      relations:
        kind === 'person'
          ? person.relations.map((entry) => (entry.to === from ? { ...entry, to } : entry))
          : person.relations,
    }
    if (changed(person, repointed)) await writeEntity(root, repointed)
  }
  if (kind === 'organization') {
    for (const project of Object.values(snapshot.projects)) {
      if (project.organization === from) await writeEntity(root, { ...project, organization: to })
    }
  }
}

/**
 * Fill in a placeholder's real identity, then move the file to the slug that identity implies —
 * so "you should meet the head of AA" ends as one coherent rename, not a stale `_`-prefixed
 * filename sitting next to a real name.
 */
export async function resolvePlaceholder(
  root: string,
  id: EntityID,
  identity: Pick<Person, 'firstname' | 'lastname' | 'email'>,
  slug: EntityID,
): Promise<EntityID> {
  const path = entityPath(root, 'person', assertSafeID(id))
  if (!(await exists(path))) throw new VaultError(`no person with id ${id}`)
  const person = decodeEntity('person', id, await readFile(path, 'utf8')) as Person
  await writeEntity(root, {
    ...person,
    ...identity,
    placeholder: false,
    descriptor: undefined,
  })
  if (!slug || slug === id) return id
  return renameEntity(root, 'person', id, await availableID(root, 'person', slug))
}

/**
 * Set a project's entire roster in one call. A diff, not a replace: only the people whose entry
 * actually changed are written, so staffing a project does not touch every person's file.
 *
 * Membership lives on the person (`projects:`), never duplicated onto the project, which is why
 * this reads as a project operation but writes person files.
 */
export async function setParticipants(
  root: string,
  projectID: EntityID,
  roster: ProjectMembership[],
): Promise<void> {
  assertSafeID(projectID)
  const wanted = new Map(roster.map((entry) => [entry.to, entry.role?.trim() || undefined]))
  const snapshot = await readVault(root)

  for (const person of Object.values(snapshot.people)) {
    const current = person.projects.find((entry) => entry.to === projectID)
    const shouldBeMember = wanted.has(person.id)
    const role = wanted.get(person.id)

    if (!shouldBeMember && !current) continue
    if (shouldBeMember && current && current.role === role) continue

    const others = person.projects.filter((entry) => entry.to !== projectID)
    const projects = shouldBeMember
      ? [...others, role ? { to: projectID, role } : { to: projectID }]
      : others
    await writeEntity(root, { ...person, projects })
  }
}

// -- logos ------------------------------------------------------------------------------------

export async function writeLogo(
  root: string,
  kind: EntityKind,
  id: EntityID,
  png: Uint8Array,
): Promise<void> {
  assertSafeID(id)
  await writeAtomically(logoPath(root, kind, id), png)
}

export async function removeLogo(root: string, kind: EntityKind, id: EntityID): Promise<void> {
  assertSafeID(id)
  await unlink(logoPath(root, kind, id)).catch(() => {})
}

export async function readLogo(
  root: string,
  kind: EntityKind,
  id: EntityID,
): Promise<Uint8Array | undefined> {
  try {
    return await readFile(logoPath(root, kind, assertSafeID(id)))
  } catch {
    return undefined
  }
}

// -- helpers ----------------------------------------------------------------------------------

/** Compares what gets written, so an unchanged person is never rewritten with an identical body. */
function changed(before: AnyEntity, after: AnyEntity): boolean {
  return encodeEntity(before) !== encodeEntity(after)
}

export type { Person, Project }
