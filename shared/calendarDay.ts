// `CalendarDay` is a `YYYY-MM-DD` string, not a Date. See the type's doc comment in types.ts for
// why. Everything here is a few lines because the format was chosen so it would be.

import type { CalendarDay } from './types.ts'

const DAY = /^(\d{4})-(\d{2})-(\d{2})$/

export function isCalendarDay(value: string): boolean {
  const match = DAY.exec(value)
  if (!match) return false
  const [, year, month, day] = match
  const date = new Date(`${year}-${month}-${day}T00:00:00Z`)
  // Rejects 2026-02-30, which the regexp alone happily accepts.
  return !Number.isNaN(date.getTime()) && date.getUTCDate() === Number(day)
}

/** Today in the *local* zone, which is the day the person clicking is actually living in. */
export function today(now: Date = new Date()): CalendarDay {
  const year = now.getFullYear()
  const month = `${now.getMonth() + 1}`.padStart(2, '0')
  const day = `${now.getDate()}`.padStart(2, '0')
  return `${year}-${month}-${day}`
}

/**
 * Coerce whatever YAML handed back. Under YAML 1.2's core schema an unquoted `2026-08-10` is
 * already a string, but a vault written by another tool under YAML 1.1 can yield a Date, and that
 * Date is a UTC midnight — so read it back in UTC to recover the day that was meant.
 */
export function toCalendarDay(value: unknown): CalendarDay | undefined {
  if (typeof value === 'string') return isCalendarDay(value.trim()) ? value.trim() : undefined
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString().slice(0, 10)
  }
  return undefined
}

/** Long form for display: `2026-08-10` → `10 August 2026`. */
export function formatCalendarDay(day: CalendarDay): string {
  if (!isCalendarDay(day)) return day
  return new Date(`${day}T00:00:00Z`).toLocaleDateString(undefined, {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  })
}
