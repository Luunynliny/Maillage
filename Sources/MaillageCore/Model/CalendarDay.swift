import Foundation

/// A calendar date with no time or timezone, serialized as `yyyy-MM-dd`.
///
/// Frontmatter dates must not carry a time component: encoding a `Date` directly
/// makes Yams emit a UTC timestamp, which shifts the day for anyone east of UTC
/// (`2026-08-06` local becomes `2026-08-05T22:00:00Z` in Paris). Storing the day
/// as three integers keeps what is written identical to what was meant.
public struct CalendarDay: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The calendar day `date` falls on in the given time zone.
    public init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = parts.year ?? 1970
        self.month = parts.month ?? 1
        self.day = parts.day ?? 1
    }

    public static func today(timeZone: TimeZone = .current) -> CalendarDay {
        CalendarDay(date: Date(), timeZone: timeZone)
    }

    /// Parses `yyyy-MM-dd`, ignoring any trailing time component.
    public init?(_ string: String) {
        let head = string.prefix(while: { $0 != "T" && $0 != " " })
        let parts = head.split(separator: "-")
        guard parts.count == 3,
            let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
            (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        self.year = y
        self.month = m
        self.day = d
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Midnight on this day, for formatting and comparisons.
    public func date(in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Unquoted `2026-08-06` is a YAML timestamp, so Yams may hand back a Date;
        // a quoted value arrives as a String. Accept either.
        if let string = try? container.decode(String.self), let parsed = CalendarDay(string) {
            self = parsed
            return
        }
        if let date = try? container.decode(Date.self) {
            // Yams parses a bare `yyyy-MM-dd` as midnight UTC, so read it back in UTC
            // to recover the day exactly as written.
            self = CalendarDay(date: date, timeZone: TimeZone(identifier: "UTC") ?? .current)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "Expected a yyyy-MM-dd date")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
