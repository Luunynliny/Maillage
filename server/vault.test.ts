import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, expect, test } from 'vitest'
import type { Organization, Person, Project } from '../shared/types.ts'
import {
  VaultError,
  availableID,
  createEntity,
  deleteEntity,
  ensureSkeleton,
  entityPath,
  logoPath,
  readVault,
  removeLogo,
  renameEntity,
  resolvePlaceholder,
  setParticipants,
  writeEntity,
  writeLogo,
} from './vault.ts'

let root: string

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'maillage-vault-'))
  await ensureSkeleton(root)
})

afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

function person(id: string, fields: Partial<Person> = {}): Person {
  return {
    kind: 'person',
    id,
    placeholder: false,
    projects: [],
    relations: [],
    body: '',
    ...fields,
  }
}

function organization(id: string, fields: Partial<Organization> = {}): Organization {
  return { kind: 'organization', id, name: id, body: '', ...fields }
}

function project(id: string, fields: Partial<Project> = {}): Project {
  return { kind: 'project', id, name: id, status: 'active', body: '', ...fields }
}

describe('reading', () => {
  test('an empty vault loads as empty, not as an error', async () => {
    const snapshot = await readVault(root)
    expect(Object.keys(snapshot.people)).toEqual([])
    expect(snapshot.issues).toEqual([])
  })

  test('the filename is the identity, whatever the frontmatter claims', async () => {
    await writeFile(entityPath(root, 'person', 'marie-dupont'), '---\nid: someone-else\n---\n')
    const snapshot = await readVault(root)
    expect(Object.keys(snapshot.people)).toEqual(['marie-dupont'])
  })

  test('a malformed file is an issue, and everything else still loads', async () => {
    await writeEntity(root, person('marie-dupont', { firstname: 'Marie' }))
    await writeFile(entityPath(root, 'person', 'broken'), '---\na: [unclosed\n---\n')
    const snapshot = await readVault(root)
    expect(snapshot.issues).toHaveLength(1)
    expect(snapshot.issues[0]!.path).toBe('people/broken.md')
    expect(snapshot.people['marie-dupont']).toBeDefined()
  })

  test('logo ids are derived by scanning assets, not read from a field', async () => {
    await writeLogo(root, 'organization', 'acme-corp', new Uint8Array([1, 2, 3]))
    expect((await readVault(root)).logoIDs.organization).toEqual(['acme-corp'])
    await removeLogo(root, 'organization', 'acme-corp')
    expect((await readVault(root)).logoIDs.organization).toEqual([])
  })

  test('ids collide only within a kind, so the same id can exist in two folders', async () => {
    await writeEntity(root, person('acme'))
    await writeEntity(root, project('acme'))
    const snapshot = await readVault(root)
    expect(snapshot.people['acme']).toBeDefined()
    expect(snapshot.projects['acme']).toBeDefined()
  })
})

describe('writing', () => {
  test('leaves no temp file behind', async () => {
    await writeEntity(root, person('marie-dupont'))
    const entries = await readdir(join(root, 'people'))
    expect(entries).toEqual(['marie-dupont.md'])
  })

  test('an id that would escape the vault is refused', async () => {
    await expect(writeEntity(root, person('../escape'))).rejects.toThrow(VaultError)
    await expect(writeEntity(root, person('..'))).rejects.toThrow(VaultError)
  })

  test('availableID disambiguates rather than clobbering', async () => {
    await writeEntity(root, person('marie-dupont'))
    expect(await availableID(root, 'person', 'marie-dupont')).toBe('marie-dupont-2')
    await writeEntity(root, person('marie-dupont-2'))
    expect(await availableID(root, 'person', 'marie-dupont')).toBe('marie-dupont-3')
  })

  test('createEntity takes the free id, leaving the existing file alone', async () => {
    await writeEntity(root, person('marie-dupont', { firstname: 'Marie' }))
    const created = await createEntity(root, person('marie-dupont', { firstname: 'Other' }))
    expect(created.id).toBe('marie-dupont-2')
    const snapshot = await readVault(root)
    expect(snapshot.people['marie-dupont']!.firstname).toBe('Marie')
  })

  test('a relation is written only to the source file', async () => {
    await writeEntity(root, person('jean-martin'))
    await writeEntity(
      root,
      person('marie-dupont', { relations: [{ to: 'jean-martin', label: 'manager of' }] }),
    )
    const jean = await readFile(entityPath(root, 'person', 'jean-martin'), 'utf8')
    expect(jean).not.toContain('relations')
    expect(jean).not.toContain('marie-dupont')
  })
})

describe('renameEntity', () => {
  test('repoints every inbound reference', async () => {
    await writeEntity(root, organization('acme'))
    await writeEntity(root, person('marie-dupont', { organization: 'acme' }))
    await writeEntity(root, project('atlas', { organization: 'acme' }))

    await renameEntity(root, 'organization', 'acme', 'acme-corp')

    const snapshot = await readVault(root)
    expect(snapshot.organizations['acme-corp']).toBeDefined()
    expect(snapshot.organizations['acme']).toBeUndefined()
    expect(snapshot.people['marie-dupont']!.organization).toBe('acme-corp')
    expect(snapshot.projects['atlas']!.organization).toBe('acme-corp')
  })

  test('repoints relations and project memberships', async () => {
    await writeEntity(root, project('atlas'))
    await writeEntity(root, person('old-id'))
    await writeEntity(
      root,
      person('marie-dupont', { relations: [{ to: 'old-id', label: 'knows' }] }),
    )
    await writeEntity(root, person('jean-martin', { projects: [{ to: 'atlas', role: 'Lead' }] }))

    await renameEntity(root, 'person', 'old-id', 'new-id')
    await renameEntity(root, 'project', 'atlas', 'atlas-2')

    const snapshot = await readVault(root)
    expect(snapshot.people['marie-dupont']!.relations).toEqual([{ to: 'new-id', label: 'knows' }])
    expect(snapshot.people['jean-martin']!.projects).toEqual([{ to: 'atlas-2', role: 'Lead' }])
  })

  test('leaves no `[[old-id]]` anywhere in the vault', async () => {
    await writeEntity(root, organization('acme'))
    await writeEntity(root, person('marie-dupont', { organization: 'acme' }))
    await renameEntity(root, 'organization', 'acme', 'acme-corp')

    for (const dir of ['people', 'organizations', 'projects']) {
      for (const file of await readdir(join(root, dir))) {
        expect(await readFile(join(root, dir, file), 'utf8')).not.toContain('[[acme]]')
      }
    }
  })

  test('the logo moves with the markdown', async () => {
    await writeEntity(root, organization('acme'))
    await writeLogo(root, 'organization', 'acme', new Uint8Array([1, 2, 3]))
    await renameEntity(root, 'organization', 'acme', 'acme-corp')

    expect((await readVault(root)).logoIDs.organization).toEqual(['acme-corp'])
    await expect(readFile(logoPath(root, 'organization', 'acme'))).rejects.toThrow()
  })

  test('refuses to overwrite an existing id', async () => {
    await writeEntity(root, person('a'))
    await writeEntity(root, person('b'))
    await expect(renameEntity(root, 'person', 'a', 'b')).rejects.toThrow(VaultError)
    expect(Object.keys((await readVault(root)).people).sort()).toEqual(['a', 'b'])
  })

  test('refuses a rename of something that is not there', async () => {
    await expect(renameEntity(root, 'person', 'ghost', 'other')).rejects.toThrow(VaultError)
  })
})

describe('deleteEntity', () => {
  test('scrubs relations, memberships, employers and project owners', async () => {
    await writeEntity(root, organization('acme'))
    await writeEntity(root, project('atlas', { organization: 'acme' }))
    await writeEntity(root, person('marie-dupont', { organization: 'acme' }))

    await deleteEntity(root, 'organization', 'acme')

    const afterOrg = await readVault(root)
    expect(afterOrg.people['marie-dupont']!.organization).toBeUndefined()
    expect(afterOrg.projects['atlas']!.organization).toBeUndefined()

    await writeEntity(root, person('jean-martin', { projects: [{ to: 'atlas' }] }))
    await deleteEntity(root, 'project', 'atlas')
    expect((await readVault(root)).people['jean-martin']!.projects).toEqual([])

    await writeEntity(root, person('zoe', { relations: [{ to: 'marie-dupont', label: 'knows' }] }))
    await deleteEntity(root, 'person', 'marie-dupont')
    expect((await readVault(root)).people['zoe']!.relations).toEqual([])
  })

  test('takes the logo with it', async () => {
    await writeEntity(root, person('marie-dupont'))
    await writeLogo(root, 'person', 'marie-dupont', new Uint8Array([1]))
    await deleteEntity(root, 'person', 'marie-dupont')
    expect((await readVault(root)).logoIDs.person).toEqual([])
  })

  test('leaves unrelated files untouched', async () => {
    await writeEntity(root, person('marie-dupont'))
    await writeEntity(
      root,
      person('jean-martin', { relations: [{ to: 'someone', label: 'knows' }] }),
    )
    const before = await readFile(entityPath(root, 'person', 'jean-martin'), 'utf8')
    await deleteEntity(root, 'person', 'marie-dupont')
    expect(await readFile(entityPath(root, 'person', 'jean-martin'), 'utf8')).toBe(before)
  })
})

describe('setParticipants', () => {
  beforeEach(async () => {
    await writeEntity(root, project('atlas'))
    await writeEntity(root, person('a'))
    await writeEntity(root, person('b'))
    await writeEntity(root, person('c'))
  })

  test('adds, updates and removes in one call', async () => {
    await setParticipants(root, 'atlas', [{ to: 'a', role: 'Lead' }, { to: 'b' }])
    let snapshot = await readVault(root)
    expect(snapshot.people['a']!.projects).toEqual([{ to: 'atlas', role: 'Lead' }])
    expect(snapshot.people['b']!.projects).toEqual([{ to: 'atlas' }])
    expect(snapshot.people['c']!.projects).toEqual([])

    await setParticipants(root, 'atlas', [{ to: 'a', role: 'Captain' }, { to: 'c' }])
    snapshot = await readVault(root)
    expect(snapshot.people['a']!.projects).toEqual([{ to: 'atlas', role: 'Captain' }])
    expect(snapshot.people['b']!.projects).toEqual([])
    expect(snapshot.people['c']!.projects).toEqual([{ to: 'atlas' }])
  })

  test('an unchanged roster rewrites nothing', async () => {
    await setParticipants(root, 'atlas', [{ to: 'a', role: 'Lead' }])
    const before = await readFile(entityPath(root, 'person', 'a'), 'utf8')
    await setParticipants(root, 'atlas', [{ to: 'a', role: 'Lead' }])
    expect(await readFile(entityPath(root, 'person', 'a'), 'utf8')).toBe(before)
  })

  test('an empty roster clears the project without touching other memberships', async () => {
    await writeEntity(root, person('a', { projects: [{ to: 'atlas' }, { to: 'other' }] }))
    await setParticipants(root, 'atlas', [])
    expect((await readVault(root)).people['a']!.projects).toEqual([{ to: 'other' }])
  })

  test('a blank role clears the role but keeps the membership', async () => {
    await setParticipants(root, 'atlas', [{ to: 'a', role: 'Lead' }])
    await setParticipants(root, 'atlas', [{ to: 'a', role: '  ' }])
    expect((await readVault(root)).people['a']!.projects).toEqual([{ to: 'atlas' }])
  })
})

describe('resolvePlaceholder', () => {
  test('fills the identity, renames the file, and keeps inbound links', async () => {
    await writeEntity(root, person('_head-of-aa', { placeholder: true, descriptor: 'Head of AA' }))
    await writeEntity(
      root,
      person('marie-dupont', {
        relations: [{ to: '_head-of-aa', label: 'should introduce me to' }],
      }),
    )

    const id = await resolvePlaceholder(
      root,
      '_head-of-aa',
      { firstname: 'Zoé', lastname: 'Muller' },
      'zoe-muller',
    )

    expect(id).toBe('zoe-muller')
    const snapshot = await readVault(root)
    const resolved = snapshot.people['zoe-muller']!
    expect(resolved.placeholder).toBe(false)
    expect(resolved.descriptor).toBeUndefined()
    expect(resolved.firstname).toBe('Zoé')
    expect(snapshot.people['_head-of-aa']).toBeUndefined()
    expect(snapshot.people['marie-dupont']!.relations).toEqual([
      { to: 'zoe-muller', label: 'should introduce me to' },
    ])
  })

  test('a slug already taken is disambiguated rather than refused', async () => {
    await writeEntity(root, person('zoe-muller'))
    await writeEntity(root, person('_someone', { placeholder: true, descriptor: 'Someone' }))
    const id = await resolvePlaceholder(
      root,
      '_someone',
      { firstname: 'Zoé', lastname: 'Muller' },
      'zoe-muller',
    )
    expect(id).toBe('zoe-muller-2')
  })
})
