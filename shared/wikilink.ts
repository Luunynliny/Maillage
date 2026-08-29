// Cross-entity links are always `[[id]]`, the way Obsidian writes them. Parsing is deliberately
// tolerant — a hand-edited vault may hold Obsidian's `[[id|display]]` or `[[id#heading]]` forms —
// but only the bare `[[id]]` is ever written back.

import type { EntityID } from './types.ts'

const WIKILINK = /^\[\[(.*)\]\]$/

/** `"[[marie-dupont|Marie]]"` → `"marie-dupont"`. Accepts a bare id too. */
export function parseWikilink(raw: string): EntityID {
  const trimmed = raw.trim()
  const inner = WIKILINK.exec(trimmed)?.[1] ?? trimmed
  // A display alias or a heading anchor is Obsidian's, not ours: both narrow to the same target.
  return inner.split('|')[0]!.split('#')[0]!.trim()
}

export function formatWikilink(id: EntityID): string {
  return `[[${id}]]`
}

export function isWikilink(raw: string): boolean {
  return WIKILINK.test(raw.trim())
}

/**
 * The one place a display name becomes an id: fold diacritics and case, collapse every run of
 * non-alphanumerics to a single dash, trim the ends. `"Zoé Müller"` → `"zoe-muller"`.
 */
export function slugify(name: string): EntityID {
  return name
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
}
