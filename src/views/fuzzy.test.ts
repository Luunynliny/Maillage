import { describe, expect, test } from 'vitest'
import { fuzzyScore } from './fuzzy.ts'

const rank = (query: string, candidates: string[]) =>
  candidates
    .map((candidate) => ({ candidate, score: fuzzyScore(query, candidate) }))
    .filter((row): row is { candidate: string; score: number } => row.score !== null)
    .sort((a, b) => b.score - a.score)
    .map((row) => row.candidate)

describe('fuzzyScore', () => {
  test('matches a subsequence, not just a substring', () => {
    expect(fuzzyScore('mdup', 'Marie Dupont')).not.toBeNull()
    expect(fuzzyScore('marie', 'Marie Dupont')).not.toBeNull()
  })

  test('returns null when a character is missing', () => {
    expect(fuzzyScore('xyz', 'Marie Dupont')).toBeNull()
  })

  test('is case-insensitive', () => {
    expect(fuzzyScore('MARIE', 'marie dupont')).not.toBeNull()
  })

  test('an empty query matches everything equally', () => {
    expect(fuzzyScore('', 'anything')).toBe(0)
  })

  test('word-start matches beat matches buried mid-word', () => {
    expect(rank('md', ['Marie Dupont', 'Command'])[0]).toBe('Marie Dupont')
  })

  test('consecutive characters beat scattered ones', () => {
    expect(rank('dup', ['Dupont', 'Diana Ulrich Palmer'])[0]).toBe('Dupont')
  })

  test('a short target wins over a long one that also matches', () => {
    expect(rank('acme', ['Acme', 'Acme Corporation International'])[0]).toBe('Acme')
  })

  test('dashes count as word starts, so an id abbreviates the way a name does', () => {
    expect(fuzzyScore('md', 'marie-dupont')).toBe(fuzzyScore('md', 'marie dupont'))
  })
})
