import { describe, expect, test } from 'vitest'
import type { Organization, Person, Project, VaultSnapshot } from '../../shared/types.ts'
import {
  buildBacklinks,
  clusterIndexOf,
  membersOfOrganization,
  participantsOfProject,
  peopleGroupedByOrganization,
  projectsInOrganization,
  usedProjectRoles,
  usedRelationLabels,
} from './derived.ts'

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

function vault(entities: (Person | Organization | Project)[]): VaultSnapshot {
  const snapshot: VaultSnapshot = {
    people: {},
    organizations: {},
    projects: {},
    logoIDs: { person: [], organization: [], project: [] },
    issues: [],
  }
  for (const entity of entities) {
    if (entity.kind === 'person') snapshot.people[entity.id] = entity
    if (entity.kind === 'organization') snapshot.organizations[entity.id] = entity
    if (entity.kind === 'project') snapshot.projects[entity.id] = entity
  }
  return snapshot
}

const acme: Organization = { kind: 'organization', id: 'acme', name: 'Acme', body: '' }
const zephyr: Organization = { kind: 'organization', id: 'zephyr', name: 'Zephyr', body: '' }
const atlas: Project = { kind: 'project', id: 'atlas', name: 'Atlas', status: 'active', body: '' }

describe('buildBacklinks', () => {
  test('inverts a one-way relation without one ever being stored', () => {
    const snapshot = vault([
      person('marie', { firstname: 'Marie', relations: [{ to: 'jean', label: 'manager of' }] }),
      person('jean', { firstname: 'Jean' }),
    ])
    expect(buildBacklinks(snapshot)['jean']).toEqual([{ from: 'marie', label: 'manager of' }])
    expect(buildBacklinks(snapshot)['marie']).toBeUndefined()
  })

  test('sorts by source name then label, so the list is stable between loads', () => {
    const snapshot = vault([
      person('zoe', { firstname: 'Zoe', relations: [{ to: 'target', label: 'knows' }] }),
      person('adam', {
        firstname: 'Adam',
        relations: [
          { to: 'target', label: 'reports to' },
          { to: 'target', label: 'friend of' },
        ],
      }),
      person('target'),
    ])
    expect(buildBacklinks(snapshot)['target']).toEqual([
      { from: 'adam', label: 'friend of' },
      { from: 'adam', label: 'reports to' },
      { from: 'zoe', label: 'knows' },
    ])
  })

  test('a relation to a person who does not exist still inverts', () => {
    const snapshot = vault([person('marie', { relations: [{ to: 'ghost', label: 'knows' }] })])
    expect(buildBacklinks(snapshot)['ghost']).toHaveLength(1)
  })
})

describe('membership', () => {
  test('an organization derives its members by scanning people', () => {
    const snapshot = vault([acme, person('marie', { organization: 'acme' }), person('jean')])
    expect(membersOfOrganization(snapshot, 'acme').map((p) => p.id)).toEqual(['marie'])
  })

  test('a project roster carries the role from the person, not the project', () => {
    const snapshot = vault([
      atlas,
      person('marie', { firstname: 'Marie', projects: [{ to: 'atlas', role: 'Lead' }] }),
      person('jean', { firstname: 'Jean', projects: [{ to: 'atlas' }] }),
      person('zoe', { firstname: 'Zoe' }),
    ])
    expect(participantsOfProject(snapshot, 'atlas')).toEqual([
      { person: snapshot.people['jean'], role: undefined },
      { person: snapshot.people['marie'], role: 'Lead' },
    ])
  })

  test('projects partition across organizations rather than overlapping', () => {
    const snapshot = vault([acme, zephyr, { ...atlas, organization: 'acme' }])
    expect(projectsInOrganization(snapshot, 'acme').map((p) => p.id)).toEqual(['atlas'])
    expect(projectsInOrganization(snapshot, 'zephyr')).toEqual([])
  })
})

describe('peopleGroupedByOrganization', () => {
  test('groups alphabetically with the unaffiliated bucket last', () => {
    const snapshot = vault([
      acme,
      zephyr,
      person('a', { organization: 'zephyr' }),
      person('b', { organization: 'acme' }),
      person('c'),
    ])
    const groups = peopleGroupedByOrganization(snapshot)
    expect(groups.map((group) => group.organization?.name)).toEqual(['Acme', 'Zephyr', undefined])
  })

  test('an employer nobody works for is omitted', () => {
    const snapshot = vault([acme, zephyr, person('a', { organization: 'acme' })])
    expect(peopleGroupedByOrganization(snapshot)).toHaveLength(1)
  })

  test('a dangling employer link lands in the unaffiliated bucket, not nowhere', () => {
    const snapshot = vault([person('a', { organization: 'gone' })])
    const groups = peopleGroupedByOrganization(snapshot)
    expect(groups).toHaveLength(1)
    expect(groups[0]!.organization).toBeUndefined()
    expect(groups[0]!.people.map((p) => p.id)).toEqual(['a'])
  })

  test('a vault with nobody in it groups into nothing', () => {
    expect(peopleGroupedByOrganization(vault([acme]))).toEqual([])
  })

  test('the cluster index is the group index, and null when unaffiliated', () => {
    const snapshot = vault([
      acme,
      zephyr,
      person('a', { organization: 'acme' }),
      person('b', { organization: 'zephyr' }),
      person('c'),
    ])
    const groups = peopleGroupedByOrganization(snapshot)
    expect(clusterIndexOf(groups, snapshot.people['a']!)).toBe(0)
    expect(clusterIndexOf(groups, snapshot.people['b']!)).toBe(1)
    expect(clusterIndexOf(groups, snapshot.people['c']!)).toBeNull()
  })
})

describe('vocabulary', () => {
  test('relation labels come back most-used first, ties broken alphabetically', () => {
    const snapshot = vault([
      person('a', {
        relations: [
          { to: 'x', label: 'knows' },
          { to: 'y', label: 'manager of' },
        ],
      }),
      person('b', {
        relations: [
          { to: 'x', label: 'manager of' },
          { to: 'z', label: 'ally of' },
        ],
      }),
    ])
    expect(usedRelationLabels(snapshot)).toEqual(['manager of', 'ally of', 'knows'])
  })

  test('project roles derive the same way and ignore the role-less', () => {
    const snapshot = vault([
      person('a', { projects: [{ to: 'atlas', role: 'Lead' }, { to: 'other' }] }),
      person('b', { projects: [{ to: 'atlas', role: 'Lead' }] }),
      person('c', { projects: [{ to: 'atlas', role: 'Pilot' }] }),
    ])
    expect(usedProjectRoles(snapshot)).toEqual(['Lead', 'Pilot'])
  })

  test('an empty vault has an empty vocabulary', () => {
    expect(usedRelationLabels(vault([]))).toEqual([])
  })
})
