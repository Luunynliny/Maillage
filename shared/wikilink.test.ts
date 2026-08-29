import { describe, expect, test } from 'vitest'
import { formatWikilink, isWikilink, parseWikilink, slugify } from './wikilink.ts'

describe('parseWikilink', () => {
  test('unwraps a plain link', () => {
    expect(parseWikilink('[[marie-dupont]]')).toBe('marie-dupont')
  })

  test('accepts a bare id', () => {
    expect(parseWikilink('marie-dupont')).toBe('marie-dupont')
  })

  test("drops Obsidian's display alias", () => {
    expect(parseWikilink('[[marie-dupont|Marie]]')).toBe('marie-dupont')
  })

  test("drops Obsidian's heading anchor", () => {
    expect(parseWikilink('[[marie-dupont#Notes]]')).toBe('marie-dupont')
  })

  test('drops both at once, alias last', () => {
    expect(parseWikilink('[[marie-dupont#Notes|Marie]]')).toBe('marie-dupont')
  })

  test('tolerates surrounding and inner whitespace', () => {
    expect(parseWikilink('  [[ marie-dupont ]] ')).toBe('marie-dupont')
  })
})

describe('isWikilink', () => {
  test('recognises the wrapped form only', () => {
    expect(isWikilink('[[a]]')).toBe(true)
    expect(isWikilink('a')).toBe(false)
    expect(isWikilink('[a]')).toBe(false)
  })
})

describe('formatWikilink', () => {
  test('round-trips with parse', () => {
    expect(parseWikilink(formatWikilink('acme-corp'))).toBe('acme-corp')
  })
})

describe('slugify', () => {
  test('lowercases and joins on dashes', () => {
    expect(slugify('Marie Dupont')).toBe('marie-dupont')
  })

  test('folds diacritics to ASCII', () => {
    expect(slugify('Zoé Müller')).toBe('zoe-muller')
  })

  test('collapses runs of punctuation to one dash', () => {
    expect(slugify('Acme, Inc. — Europe')).toBe('acme-inc-europe')
  })

  test('trims leading and trailing dashes', () => {
    expect(slugify('  ¡Hola!  ')).toBe('hola')
  })

  test('keeps digits', () => {
    expect(slugify('Robot 1-X')).toBe('robot-1-x')
  })

  test('a name with nothing sluggable yields an empty id', () => {
    expect(slugify('!!!')).toBe('')
  })
})
