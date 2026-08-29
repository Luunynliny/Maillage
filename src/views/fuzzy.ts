/**
 * Subsequence matching, not substring: "mdup" finds "Marie Dupont". Consecutive characters and
 * characters at the start of a word score higher, so the abbreviation someone would actually type
 * beats an accidental scattering of the same letters somewhere else.
 *
 * Returns null when the needle is not a subsequence of the haystack at all.
 */
export function fuzzyScore(needle: string, haystack: string): number | null {
  const query = needle.toLowerCase()
  const target = haystack.toLowerCase()
  if (!query) return 0

  let score = 0
  let cursor = 0
  let previous = -2

  for (const character of query) {
    const found = target.indexOf(character, cursor)
    if (found === -1) return null
    score += 1
    if (found === previous + 1) score += 3
    if (found === 0 || target[found - 1] === ' ' || target[found - 1] === '-') score += 5
    previous = found
    cursor = found + 1
  }

  // A short target that matches is a better answer than a long one that also does.
  return score + Math.max(0, 12 - target.length / 2)
}
