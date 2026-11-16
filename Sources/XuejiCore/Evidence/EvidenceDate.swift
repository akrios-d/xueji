import Foundation

/// A date of the evidence timeline, known to the year, to the month or to the day.
public struct EvidenceDate: Codable, Equatable, Hashable, Sendable {
    public var year: Int
    /// 1 to 12.
    public var month: Int?
    /// Only with a month.
    public var day: Int?

    public static let years = 1900...2100

    public init(year: Int, month: Int? = nil, day: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
    }

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return 31 }
        return range.count
    }

    /// The year is in range, the month is 1 to 12 and the day exists in that month.
    public var isValid: Bool {
        guard Self.years.contains(year) else { return false }
        guard let month else { return day == nil }
        guard (1...12).contains(month) else { return false }
        guard let day else { return true }
        return (1...Self.daysIn(month: month, year: year)).contains(day)
    }

    /// As the report writes it: "2019", "Feb 2019", "4 Nov 2019".
    public var label: String {
        guard let month, (1...12).contains(month) else { return "\(year)" }
        let name = Self.monthNames[month - 1]
        if let day { return "\(day) \(name) \(year)" }
        return "\(name) \(year)"
    }

    /// The first moment of the day, the month or the year.
    public var start: Date {
        Self.calendar.date(from: DateComponents(year: year, month: month ?? 1, day: day ?? 1)) ?? .distantPast
    }

    /// Where the next day, month or year begins.
    public var end: Date {
        let unit: Calendar.Component = day != nil ? .day : (month != nil ? .month : .year)
        return Self.calendar.date(byAdding: unit, value: 1, to: start) ?? start
    }

    /// Where it stands on a time axis: the middle of the day, of the month or of the year.
    public var date: Date {
        Date(timeIntervalSince1970: (start.timeIntervalSince1970 + end.timeIntervalSince1970) / 2)
    }

    /// "2019", or "2019 – 2023" for a period.
    public static func label(from: EvidenceDate, until: EvidenceDate?) -> String {
        guard let until, until != from else { return from.label }
        return "\(from.label) – \(until.label)"
    }

    /// Reads a date written as text: "2019", "Feb 2019", "5 Jun 2019", "4–5 Nov 2019", "2019-11-04".
    /// A range gives its first day. Returns nil when there is no year.
    public static func parse(_ text: String) -> EvidenceDate? {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let iso = captures(#"^(\d{4})-(\d{1,2})(?:-(\d{1,2}))?$"#, in: source),
           let year = Int(iso[0]), let month = Int(iso[1]) {
            return validated(EvidenceDate(year: year, month: month, day: iso.count > 2 ? Int(iso[2]) : nil))
        }
        guard let found = captures(#"\b((?:19|20)\d{2})\b"#, in: source), let year = Int(found[0]) else { return nil }
        var month: Int?
        if let name = captures(#"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b"#, in: source.lowercased()) {
            month = monthNames.firstIndex { $0.lowercased() == name[0] }.map { $0 + 1 }
        }
        var day: Int?
        if month != nil {
            let rest = source.replacingOccurrences(of: found[0], with: " ")
            if let digits = captures(#"\b(\d{1,2})\b"#, in: rest) { day = Int(digits[0]) }
        }
        return validated(EvidenceDate(year: year, month: month, day: day))
    }

    /// Reads a date or a period written as text: "2019–2023", "Feb–Jun 2019", "4–5 Nov 2019", "Nov 2018 - Feb 2019".
    /// What one side leaves out is taken from the other ("4–5 Nov 2019" is 4 Nov 2019 to 5 Nov 2019).
    public static func parsePeriod(_ text: String) -> (from: EvidenceDate, until: EvidenceDate?)? {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isoDate = source.range(of: #"^\d{4}-\d{1,2}(-\d{1,2})?$"#, options: .regularExpression) != nil
        let pattern = #"^(.+?)\s*(?:–|—|\s-\s|\s+to\s+|(?<=\d)-(?=\d))\s*(.+)$"#
        guard !isoDate, let sides = captures(pattern, in: source), sides.count == 2 else {
            return parse(source).map { ($0, nil) }
        }
        var left = loose(sides[0])
        var right = loose(sides[1])
        if left.month == nil, left.day != nil, left.year == nil { left.month = right.month }
        if left.year == nil { left.year = right.year }
        if right.year == nil { right.year = left.year }
        guard let from = validated(left.date), let until = validated(right.date) else {
            return parse(source).map { ($0, nil) }
        }
        return until.start < from.start ? (from, nil) : (from, until == from ? nil : until)
    }

    private struct Parts {
        var year: Int?
        var month: Int?
        var day: Int?

        var date: EvidenceDate { EvidenceDate(year: year ?? 0, month: month, day: month == nil ? nil : day) }
    }

    /// The year, the month and the day that a piece of text names, each when it names one.
    private static func loose(_ text: String) -> Parts {
        var parts = Parts()
        var rest = text
        if let found = captures(#"\b((?:19|20)\d{2})\b"#, in: text), let year = Int(found[0]) {
            parts.year = year
            rest = rest.replacingOccurrences(of: found[0], with: " ")
        }
        if let name = captures(#"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b"#, in: text.lowercased()) {
            parts.month = monthNames.firstIndex { $0.lowercased() == name[0] }.map { $0 + 1 }
        }
        if let digits = captures(#"\b(\d{1,2})\b"#, in: rest) { parts.day = Int(digits[0]) }
        return parts
    }

    /// Drops what does not exist (a 31st of February) instead of refusing the whole date.
    private static func validated(_ value: EvidenceDate) -> EvidenceDate? {
        if value.isValid { return value }
        var smaller = value
        smaller.day = nil
        if smaller.isValid { return smaller }
        smaller.month = nil
        return smaller.isValid ? smaller : nil
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location != NSNotFound, let swiftRange = Range(range, in: text) { groups.append(String(text[swiftRange])) }
        }
        return groups.isEmpty ? nil : groups
    }
}
