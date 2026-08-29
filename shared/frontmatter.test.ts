import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, test } from 'vitest'
import {
  FrontmatterError,
  decodeEntity,
  encodeEntity,
  joinFrontmatter,
  splitFrontmatter,
} from './frontmatter.ts'
import type { EntityKind, Person, Project } from './types.ts'
import { KIND_DIRECTORY, ENTITY_KINDS } from './types.ts'

const FIXTURES = fileURLToPath(new URL('./__fixtures__/vault', import.meta.url))

describe('golden files', () => {
  // Every file in the fixture vault was written by the Swift app's Yams encoder. Decoding and
  // re-encoding one must reproduce it byte for byte, or every save in the new app would rewrite
  // quoting and indentation across a git-tracked vault.
  for (const kind of ENTITY_KINDS) {
    const dir = join(FIXTURES, KIND_DIRECTORY[kind])
    for (const file of readdirSync(dir).filter((name) => name.endsWith('.md'))) {
      test(`${KIND_DIRECTORY[kind]}/${file} round-trips byte for byte`, () => {
        const original = readFileSync(join(dir, file), 'utf8')
        const id = file.slice(0, -'.md'.length)
        expect(encodeEntity(decodeEntity(kind, id, original))).toBe(original)
      })
    }
  }

  test('the fixture vault is not empty', () => {
    const counts = ENTITY_KINDS.map(
      (kind: EntityKind) => readdirSync(join(FIXTURES, KIND_DIRECTORY[kind])).length,
    )
    expect(counts.every((count) => count > 0)).toBe(true)
  })
})

describe('splitFrontmatter', () => {
  test('separates yaml from body', () => {
    const { yaml, body } = splitFrontmatter('---\nid: a\n---\n\nHello.\n')
    expect(yaml).toBe('id: a')
    expect(body).toBe('Hello.')
  })

  test('tolerates a file with no body', () => {
    expect(splitFrontmatter('---\nid: a\n---\n').body).toBe('')
  })

  test('tolerates no trailing newline after the closing fence', () => {
    expect(splitFrontmatter('---\nid: a\n---').yaml).toBe('id: a')
  })

  test('keeps blank lines and markdown inside the body', () => {
    const body = 'One.\n\n- two\n- three'
    expect(splitFrontmatter(joinFrontmatter('id: a', body)).body).toBe(body)
  })

  test('a file without frontmatter is an error, not a guess', () => {
    expect(() => splitFrontmatter('Just notes.\n')).toThrow(FrontmatterError)
  })

  test('a `---` inside the body does not re-open the frontmatter', () => {
    const { body } = splitFrontmatter('---\nid: a\n---\n\nBefore.\n\n---\n\nAfter.\n')
    expect(body).toBe('Before.\n\n---\n\nAfter.')
  })
})

describe('decodeEntity', () => {
  const person = (yaml: string, body = '') =>
    decodeEntity('person', 'someone', joinFrontmatter(yaml, body)) as Person

  test('the filename wins over a disagreeing frontmatter id', () => {
    expect(person('id: not-this\ntype: person').id).toBe('someone')
  })

  test('malformed yaml raises a FrontmatterError', () => {
    expect(() => decodeEntity('person', 'x', '---\na: [unclosed\n---\n')).toThrow(FrontmatterError)
  })

  test('frontmatter that is not a mapping raises', () => {
    expect(() => decodeEntity('person', 'x', '---\n- a\n- b\n---\n')).toThrow(FrontmatterError)
  })

  test('wikilinks decode to bare ids', () => {
    expect(person("organization: '[[acme-corp]]'").organization).toBe('acme-corp')
  })

  test("Obsidian's alias and heading forms narrow to the target", () => {
    expect(person("organization: '[[acme-corp|Acme]]'").organization).toBe('acme-corp')
    expect(person("organization: '[[acme-corp#About]]'").organization).toBe('acme-corp')
  })

  test('the retired plural organizations key still decodes, first entry winning', () => {
    const decoded = person("organizations:\n- '[[acme-corp]]'\n- '[[other]]'")
    expect(decoded.organization).toBe('acme-corp')
  })

  test('a project membership decodes from either the bare or the mapping form', () => {
    const decoded = person("projects:\n- '[[atlas]]'\n- to: '[[maillage]]'\n  role: Lead")
    expect(decoded.projects).toEqual([{ to: 'atlas' }, { to: 'maillage', role: 'Lead' }])
  })

  test('a relation missing its label is dropped rather than half-decoded', () => {
    expect(person("relations:\n- to: '[[jean]]'").relations).toEqual([])
  })

  test('placeholder defaults to false and blank strings become undefined', () => {
    const decoded = person('firstname: "  "')
    expect(decoded.placeholder).toBe(false)
    expect(decoded.firstname).toBeUndefined()
  })

  test('an unknown project status falls back to active', () => {
    const project = decodeEntity('project', 'p', '---\nstatus: whatever\n---\n') as Project
    expect(project.status).toBe('active')
  })
})

describe('encodeEntity', () => {
  const base: Person = {
    kind: 'person',
    id: 'marie-dupont',
    firstname: 'Marie',
    lastname: 'Dupont',
    placeholder: false,
    projects: [],
    relations: [],
    created: '2026-08-06',
    body: 'Met at the Paris conference.',
  }

  test('writes keys in the declared order, never sorted', () => {
    const keys = [...encodeEntity(base).matchAll(/^(\w+):/gm)].map((match) => match[1])
    expect(keys).toEqual(['id', 'type', 'firstname', 'lastname', 'placeholder', 'created'])
  })

  test('wikilinks and days are single-quoted', () => {
    const encoded = encodeEntity({ ...base, organization: 'acme-corp' })
    expect(encoded).toContain("organization: '[[acme-corp]]'")
    expect(encoded).toContain("created: '2026-08-06'")
  })

  test('empty projects and relations are omitted entirely', () => {
    expect(encodeEntity(base)).not.toContain('projects')
    expect(encodeEntity(base)).not.toContain('relations')
  })

  test('a role-less membership stays a bare wikilink; a role expands it', () => {
    const encoded = encodeEntity({
      ...base,
      projects: [{ to: 'atlas' }, { to: 'maillage', role: 'Lead' }],
    })
    expect(encoded).toContain("projects:\n- '[[atlas]]'\n- to: '[[maillage]]'\n  role: Lead\n")
  })

  test('sequences are flush with their key, as Yams wrote them', () => {
    const encoded = encodeEntity({
      ...base,
      relations: [{ to: 'jean-martin', label: 'manager of' }],
    })
    expect(encoded).toContain("relations:\n- to: '[[jean-martin]]'\n  label: manager of\n")
  })

  test('a long list of wikilinks is never folded mid-array', () => {
    const relations = Array.from({ length: 8 }, (_, index) => ({
      to: `a-rather-long-person-identifier-${index}`,
      label: 'knows',
    }))
    for (const line of encodeEntity({ ...base, relations }).split('\n')) {
      expect(line.startsWith(' ') || !line.includes('  ')).toBe(true)
    }
  })

  test('placeholder is written even when false', () => {
    expect(encodeEntity(base)).toContain('placeholder: false')
  })

  test('an empty body writes no trailing blank line', () => {
    expect(encodeEntity({ ...base, body: '' }).endsWith('---\n')).toBe(true)
  })

  test('the legacy plural key is migrated on save', () => {
    const decoded = decodeEntity(
      'person',
      'someone',
      "---\ntype: person\norganizations:\n- '[[acme-corp]]'\n---\n",
    )
    const encoded = encodeEntity(decoded)
    expect(encoded).toContain("organization: '[[acme-corp]]'")
    expect(encoded).not.toContain('organizations:')
  })
})
