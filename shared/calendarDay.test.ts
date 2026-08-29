import { describe, expect, test } from 'vitest'
import { formatCalendarDay, isCalendarDay, toCalendarDay, today } from './calendarDay.ts'

describe('isCalendarDay', () => {
  test('accepts a well-formed day', () => {
    expect(isCalendarDay('2026-08-06')).toBe(true)
  })

  test('rejects a day that does not exist', () => {
    expect(isCalendarDay('2026-02-30')).toBe(false)
  })

  test('rejects other shapes', () => {
    expect(isCalendarDay('2026-8-6')).toBe(false)
    expect(isCalendarDay('06/08/2026')).toBe(false)
    expect(isCalendarDay('')).toBe(false)
  })
})

describe('today', () => {
  test('reads the local calendar day, not the UTC one', () => {
    // 00:30 local on the 7th is still the 6th in UTC for anyone east of it. The day someone is
    // living in is the day that gets written.
    const localMidnightish = new Date(2026, 7, 7, 0, 30)
    expect(today(localMidnightish)).toBe('2026-08-07')
  })

  test('zero-pads month and day', () => {
    expect(today(new Date(2026, 0, 5))).toBe('2026-01-05')
  })
})

describe('toCalendarDay', () => {
  test('passes a valid string through, trimmed', () => {
    expect(toCalendarDay(' 2026-08-06 ')).toBe('2026-08-06')
  })

  test('recovers the intended day from a UTC-midnight Date', () => {
    expect(toCalendarDay(new Date('2026-08-06T00:00:00Z'))).toBe('2026-08-06')
  })

  test('returns undefined for anything else', () => {
    expect(toCalendarDay(undefined)).toBeUndefined()
    expect(toCalendarDay(42)).toBeUndefined()
    expect(toCalendarDay('not a day')).toBeUndefined()
  })
})

describe('ordering', () => {
  test('string compare is chronological compare for this format', () => {
    const days = ['2026-08-10', '2025-12-31', '2026-01-02']
    expect([...days].sort()).toEqual(['2025-12-31', '2026-01-02', '2026-08-10'])
  })
})

describe('formatCalendarDay', () => {
  test('does not shift the day when formatting', () => {
    expect(formatCalendarDay('2026-08-06')).toContain('6')
    expect(formatCalendarDay('2026-08-06')).toContain('2026')
  })

  test('passes an unparseable value through untouched', () => {
    expect(formatCalendarDay('soon')).toBe('soon')
  })
})
