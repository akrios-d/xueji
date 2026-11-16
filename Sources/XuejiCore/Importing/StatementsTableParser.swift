import Foundation

/// Reads a "who said what, and when" table: Date | Who (and where) | Position taken | Where to find it | Ref,
/// grouped under "Period N (...)" headings, followed by a numbered reference list.
enum StatementsTableParser {
    private static let tableColumns = 4 // date, who, position, where; the fifth column holds the reference numbers
    private static let referenceColumn = 4

    private struct Row {
        var phase: String
        var primary: Int
        var more: [Int] = []
        var cells: [[[ImportWord]]]
    }

    private enum Mode { case table, references, stopped }
    private enum Event { case phase(String), references, stop }

    /// `nil` when no page has the table's heading.
    static func parse(_ pages: [ImportPage]) -> (statements: [ImportedStatement], references: [Int: ImportedReference])? {
        var rows: [Row] = []
        var current: Int?
        var phase = ""
        var mode = Mode.table
        var starts: [Double]?
        var sawHeader = false
        var referenceTexts: [Int: String] = [:]
        var currentReference: Int?

        for page in pages {
            let body = TableLayout.removingFooter(page.words)
            if let header = TableLayout.headerLine(in: body, containing: ["Date", "Who", "Position", "Ref"]),
               let found = columnStarts(header) {
                starts = found
                sawHeader = true
            }

            // Cut the page at each heading; a zone then belongs to the heading above it.
            let events = findEvents(in: body, starts: starts)
            var zones: [(from: Double, to: Double, event: Event?)] = []
            var from = -Double.infinity
            var pending: Event?
            for found in events {
                zones.append((from, found.top, pending))
                from = found.top
                pending = found.event
            }
            zones.append((from, .infinity, pending))

            for zone in zones {
                if let event = zone.event {
                    current = nil
                    switch event {
                    case .phase(let text):
                        phase = text
                        mode = .table
                    case .references:
                        mode = .references
                    case .stop:
                        mode = .stopped
                    }
                }
                let words = body.filter { word in
                    guard word.top >= zone.from, word.top < zone.to else { return false }
                    // The heading line itself is not content.
                    return zone.event == nil || abs(word.top - zone.from) > TableLayout.lineTolerance
                }

                switch mode {
                case .stopped:
                    continue
                case .references:
                    for line in TableLayout.lines(words) {
                        let text = line.map(\.text).joined(separator: " ")
                        if let start = ReferenceParser.numberedStart(text) {
                            referenceTexts[start.number] = start.text
                            currentReference = start.number
                        } else if let number = currentReference {
                            let previous = referenceTexts[number] ?? ""
                            let lastToken = previous.split(separator: " ").last.map(String.init) ?? ""
                            // A link that wraps carries on without a space.
                            referenceTexts[number] = lastToken.hasPrefix("http") ? previous + text : previous + " " + text
                        }
                    }
                case .table:
                    guard let starts else { continue }
                    appendRows(words: words, starts: starts, phase: phase, rows: &rows, current: &current)
                }
            }
        }

        guard sawHeader else { return nil }
        let references = Dictionary(
            uniqueKeysWithValues: referenceTexts.map { ($0.key, ReferenceParser.parse(number: $0.key, text: $0.value)) }
        )
        return (rows.compactMap(makeStatement), references)
    }

    // MARK: Rows

    private static func appendRows(
        words allWords: [ImportWord], starts: [Double], phase: String, rows: inout [Row], current: inout Int?
    ) {
        func column(_ word: ImportWord) -> Int { TableLayout.columnIndex(of: word.x0, starts: starts) }

        var words = allWords
        // Drop the table's own heading, which repeats under every period and on every page.
        if let header = TableLayout.headerLine(in: words, containing: ["Date", "Who", "Position", "Ref"]) {
            let top = header.map(\.top).min() ?? 0
            let bottom = header.map(\.bottom).max() ?? 0
            words.removeAll { header.contains($0) || ($0.text == "phrase)" && $0.top > top && $0.top < bottom + 20) }
        }

        // A row starts on the line that has both a date and a reference number. A second reference number on a
        // later line of the same row has no date next to it.
        let references = words.filter { column($0) == referenceColumn && referenceNumber($0.text) != nil }
        let rowStarts = references
            .filter { reference in
                words.contains { column($0) == 0 && abs($0.top - reference.top) <= TableLayout.lineTolerance }
            }
            .sorted { $0.top < $1.top }
        let bounds = rowStarts.map { $0.top - 2 }

        // Words above the first row continue the row from the previous page.
        if let index = current {
            addChunk(words.filter { $0.top < (bounds.first ?? .infinity) }, toRowAt: index, rows: &rows, column: column)
        }
        for (position, start) in rowStarts.enumerated() {
            let upper = position + 1 < bounds.count ? bounds[position + 1] : Double.infinity
            let emptyCell: [[ImportWord]] = [[]]
            rows.append(Row(
                phase: phase,
                primary: referenceNumber(start.text) ?? 0,
                cells: Array(repeating: emptyCell, count: tableColumns)
            ))
            current = rows.count - 1
            let segment = words.filter { $0.top >= bounds[position] && $0.top < upper }
            for word in segment where column(word) == referenceColumn {
                if let number = referenceNumber(word.text), number != rows[rows.count - 1].primary {
                    rows[rows.count - 1].more.append(number)
                }
            }
            fill(segment, intoRowAt: rows.count - 1, rows: &rows, column: column, newChunk: false)
        }
    }

    private static func addChunk(
        _ words: [ImportWord], toRowAt index: Int, rows: inout [Row], column: (ImportWord) -> Int
    ) {
        guard !words.isEmpty else { return }
        fill(words, intoRowAt: index, rows: &rows, column: column, newChunk: true)
    }

    private static func fill(
        _ words: [ImportWord], intoRowAt index: Int, rows: inout [Row], column: (ImportWord) -> Int, newChunk: Bool
    ) {
        if newChunk {
            for cell in 0..<tableColumns { rows[index].cells[cell].append([]) }
        }
        for word in words {
            let target = column(word)
            guard target < tableColumns else { continue }
            rows[index].cells[target][rows[index].cells[target].count - 1].append(word)
        }
    }

    private static func findEvents(
        in words: [ImportWord], starts: [Double]?
    ) -> [(top: Double, event: Event)] {
        var events: [(top: Double, event: Event)] = []
        for line in TableLayout.lines(words) {
            guard let first = line.first else { continue }
            let atMargin = starts.map { first.x0 < $0[1] - 2.5 } ?? true
            let text = line.map(\.text).joined(separator: " ")
            if first.text == "Period", line.count > 1, Int(line[1].text) != nil, atMargin {
                events.append((first.top, .phase(text)))
            } else if first.text == "References", line.count == 1 {
                events.append((first.top, .references))
            } else if first.text == "Caveats:", atMargin {
                events.append((first.top, .stop))
            }
        }
        return events.sorted { $0.top < $1.top }
    }

    private static func columnStarts(_ header: [ImportWord]) -> [Double]? {
        let names = ["Date", "Who", "Position", "Where", "Ref"]
        let starts = names.compactMap { TableLayout.start(of: $0, in: header) }
        return starts.count == names.count ? starts : nil
    }

    private static func referenceNumber(_ text: String) -> Int? {
        guard text.hasPrefix("["), text.hasSuffix("]") else { return nil }
        return Int(text.dropFirst().dropLast())
    }

    // MARK: Statements

    private static func makeStatement(_ row: Row) -> ImportedStatement? {
        let dateLabel = TableLayout.text(of: row.cells[0])
        let who = TableLayout.text(of: row.cells[1])
        let position = TableLayout.text(of: row.cells[2])
        let locator = TableLayout.text(of: row.cells[3])

        var actor = who
        var kind: String?
        var context = ""
        if let groups = ImportText.captures(#"^(.*)\((S|TT|M|C|G)\)\s*(.*)$"#, in: who, options: [.dotMatchesLineSeparators]) {
            actor = groups[0].trimmingCharacters(in: .whitespaces)
            kind = actorKind(code: groups[1])
            context = groups[2]
        }
        guard !actor.isEmpty, !position.isEmpty else { return nil }

        let date = parseDate(dateLabel)
        return ImportedStatement(
            actor: actor,
            actorKind: kind,
            dateLabel: dateLabel,
            date: date.day,
            isApproximate: date.approximate,
            phase: row.phase,
            position: position,
            locator: locator,
            context: context,
            referenceNumbers: [row.primary] + row.more
        )
    }

    private static func actorKind(code: String) -> String? {
        switch code {
        case "S": return "scholar"
        case "TT": return "thinkTank"
        case "M": return "media"
        case "C": return "citizens"
        case "G": return "government"
        default: return nil
        }
    }

    private static let monthNames = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
    ]

    /// "13 Jul 2011" is exact. "Nov 2016", "2010", "c. 31 Jul 2016" and "2016 (month not confirmed)" are
    /// approximate: the missing part is set to the first of the month or year.
    static func parseDate(_ label: String) -> (day: CalendarDay?, approximate: Bool) {
        guard let year = ImportText.years(in: label).first else { return (nil, true) }
        let lower = label.lowercased()
        var approximate = lower.contains("c.") || lower.contains("confirme")
        var month: Int?
        var day: Int?
        for token in lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) {
            if month == nil, token.count >= 3, let index = monthNames.firstIndex(where: { $0.hasPrefix(token) }) {
                month = index + 1
            } else if day == nil, let number = Int(token), (1...31).contains(number) {
                day = number
            }
        }
        if month == nil || day == nil { approximate = true }
        return (CalendarDay(year: year, month: month ?? 1, day: day ?? 1), approximate)
    }
}
