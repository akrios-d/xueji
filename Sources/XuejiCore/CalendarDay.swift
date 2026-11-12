import Foundation

/// A day on the calendar with no time of day and no time zone, so a deadline never shifts when the
/// Mac changes time zone. Convert to a `Date` only at the edges (display, EventKit).
public struct CalendarDay: Hashable, Comparable, Codable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Midnight at the start of this day.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int, in calendar: Calendar = .current) -> CalendarDay {
        let start = date(in: calendar)
        return CalendarDay(calendar.date(byAdding: .day, value: days, to: start) ?? start, calendar: calendar)
    }

    public func adding(months: Int, in calendar: Calendar = .current) -> CalendarDay {
        let start = date(in: calendar)
        return CalendarDay(calendar.date(byAdding: .month, value: months, to: start) ?? start, calendar: calendar)
    }

    /// Whole days from this day to `other` (negative when `other` is earlier).
    public func days(until other: CalendarDay, in calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: date(in: calendar), to: other.date(in: calendar)).day ?? 0
    }

    public var startOfMonth: CalendarDay {
        CalendarDay(year: year, month: month, day: 1)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
