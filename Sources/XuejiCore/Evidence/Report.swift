import Foundation

/// Background colour of a table cell or a note.
public enum ReportShade: String, Equatable, Sendable {
    case header, gap, essential, supporting, counter, note

    /// "RRGGBB"
    var fill: String {
        switch self {
        case .header: return "E7E6E6"
        case .gap: return "FADBD8"
        case .essential: return "D5E8D4"
        case .supporting: return "DAE8FC"
        case .counter: return "FFE6CC"
        case .note: return "FFF2CC"
        }
    }
}

public struct ReportCell: Equatable, Sendable, ExpressibleByStringLiteral {
    public var text: String
    public var shade: ReportShade?
    public var bold: Bool

    public init(_ text: String, shade: ReportShade? = nil, bold: Bool = false) {
        self.text = text
        self.shade = shade
        self.bold = bold
    }

    public init(stringLiteral value: String) { self.init(value) }
}

public struct ReportColumn: Equatable, Sendable {
    public var title: String
    /// Relative width.
    public var weight: Int

    public init(_ title: String, weight: Int = 1) {
        self.title = title
        self.weight = max(weight, 1)
    }
}

/// One piece of a report made of text and tables (the triage report).
public enum ReportBlock: Equatable, Sendable {
    case title(String)
    case subtitle(String)
    case heading(String)
    case paragraph(String)
    case callout(String, ReportShade)
    case table(columns: [ReportColumn], rows: [[ReportCell]])

    /// Plain text: paragraphs separated by a blank line, tables with one row per line and tabs between columns.
    public static func plainText(_ blocks: [ReportBlock]) -> String {
        blocks.map { block -> String in
            switch block {
            case .title(let text), .subtitle(let text), .heading(let text), .paragraph(let text), .callout(let text, _):
                return text
            case .table(let columns, let rows):
                let header = columns.map(\.title).joined(separator: "\t")
                let lines = rows.map { $0.map { $0.text.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\t") }
                return ([header] + lines).joined(separator: "\n")
            }
        }
        .joined(separator: "\n\n")
    }
}
