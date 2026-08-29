// What a merge into main will actually publish, checked against the real `.releaserc.json`.
//
// This exists because the release config has now failed silently twice, and a release that goes
// wrong goes wrong exactly once, in public, on the commit you cared about most:
//
//   1. semantic-release's default `angular` preset cannot parse a `feat!:` header at all, so a
//      breaking change published *no release* rather than a major one.
//   2. Fixing that by naming the `conventionalcommits` preset, without pinning it to the version
//      line the rest of the toolchain is on, left the analyzer working and the notes writer
//      emitting nothing — v1.0.0 shipped with an empty changelog.
//
// Neither failed loudly. Both are one assertion away from impossible.

import { readFileSync } from 'node:fs'
import { analyzeCommits } from '@semantic-release/commit-analyzer'
import { generateNotes } from '@semantic-release/release-notes-generator'
import { describe, expect, test } from 'vitest'

/** The plugin's options exactly as `.releaserc.json` gives them to semantic-release. */
function optionsFor(plugin: string): Record<string, unknown> {
  const rc = JSON.parse(readFileSync(new URL('./.releaserc.json', import.meta.url), 'utf8')) as {
    plugins: (string | [string, Record<string, unknown>])[]
  }
  const entry = rc.plugins.find((p) => (Array.isArray(p) ? p[0] : p) === plugin)
  if (!entry) throw new Error(`${plugin} is not in .releaserc.json`)
  return Array.isArray(entry) ? entry[1] : {}
}

function contextFor(subject: string) {
  return {
    commits: [
      {
        hash: 'a'.repeat(40),
        message: `${subject}\n`,
        subject,
        author: {},
        committer: {},
      },
    ],
    lastRelease: { version: '1.0.0', gitTag: 'v1.0.0' },
    nextRelease: { version: '1.1.0', gitTag: 'v1.1.0', type: 'minor' },
    options: { repositoryUrl: 'https://github.com/Luunynliny/Maillage' },
    cwd: process.cwd(),
    logger: { log: () => {} },
  }
}

const bumpFor = (subject: string) =>
  analyzeCommits(optionsFor('@semantic-release/commit-analyzer'), contextFor(subject))

const notesFor = async (subject: string) => {
  const notes = await generateNotes(
    optionsFor('@semantic-release/release-notes-generator'),
    contextFor(subject),
  )
  // Drop the version heading, which is always present whether or not anything was written under it.
  return notes.split('\n').slice(1).join('\n').trim()
}

describe('the bump a PR title produces', () => {
  test('`feat!:` is a major release', async () => {
    expect(await bumpFor('feat!: replace the thing')).toBe('major')
  })

  test('a scoped `feat(x)!:` is a major release too', async () => {
    expect(await bumpFor('feat(graph)!: walk more than one hop')).toBe('major')
  })

  test('a `BREAKING CHANGE:` footer is a major release', async () => {
    expect(await bumpFor('feat: a thing\n\nBREAKING CHANGE: everything moved')).toBe('major')
  })

  test('`feat:` is a minor release and `fix:` is a patch', async () => {
    expect(await bumpFor('feat: add a thing')).toBe('minor')
    expect(await bumpFor('fix: fix a thing')).toBe('patch')
  })

  test('the housekeeping types release nothing', async () => {
    for (const type of ['chore', 'ci', 'docs', 'style', 'test', 'refactor']) {
      expect(await bumpFor(`${type}: shuffle things about`)).toBeNull()
    }
  })
})

describe('the notes a release publishes', () => {
  test('a feature is written down, not just counted', async () => {
    const notes = await notesFor('feat: add a thing')
    expect(notes).toContain('Features')
    expect(notes).toContain('add a thing')
  })

  test('a fix is written down', async () => {
    expect(await notesFor('fix: fix a thing')).toContain('fix a thing')
  })

  test('a breaking change gets its own section', async () => {
    const notes = await notesFor('feat!: replace the macOS app with a local web app')
    expect(notes).toContain('BREAKING CHANGES')
    expect(notes).toContain('replace the macOS app with a local web app')
  })

  test('the analyzer and the writer agree — anything that releases also gets notes', async () => {
    // The failure mode that shipped an empty v1.0.0: a bump computed, and nothing written under it.
    for (const subject of ['feat!: a breaking thing', 'feat: a thing', 'fix: a thing']) {
      expect(await bumpFor(subject)).not.toBeNull()
      expect(await notesFor(subject)).not.toBe('')
    }
  })
})
