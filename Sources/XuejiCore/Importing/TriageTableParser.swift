import Foundation

/// Reads a "source triage" table: # | Period | Source | Link | Classification | Triage note.
enum TriageTableParser {
    private static let columnCount = 6

    private struct Row {
        var number: Int
        /// Per column, the words of each page chunk the row spans.
        var cells: [[[ImportWord]]]
    }

    /// `nil` when no page has the table's heading.
    static func parse(_ pages: [ImportPage]) -> [ImportedSource]? {
        var rows: [Row] = []
        var sawHeader = false
        var knownStarts: [Double]?
        // The table goes on over pages that do not repeat its heading, until text at the left edge ends it.
        var isActive = false

        for page in pages {
            let words = TableLayout.removingFooter(page.words)
            let header = TableLayout.headerLine(in: words, containing: ["#", "Source", "Link", "Triage"])
            if let header {
                guard let found = columnStarts(header) else { continue }
                knownStarts = found
                isActive = true
                sawHeader = true
            } else if !isActive {
                continue
            }
            guard let starts = knownStarts else { continue }

            let headerTop = header?.map(\.top).min() ?? -Double.infinity
            let headerBottom = header?.map(\.bottom).max() ?? -Double.infinity
            func column(_ word: ImportWord) -> Int { TableLayout.columnIndex(of: word.x0, starts: starts) }

            let body = words.filter { word in
                guard word.top > headerTop, !(header?.contains(word) ?? false) else { return false }
                // The wrapped end of the "Classification" heading ("Classificati" / "on").
                let isHeadingTail = header != nil && word.text == "on" && column(word) == 4 && word.top < headerBottom + 20
                return !isHeadingTail
            }

            let numbers = body
                .filter { column($0) == 0 && Int($0.text) != nil }
                .sorted { $0.top < $1.top }
            // Text at the left edge that is not a row number ends the table (the title of what follows).
            let stop = Self.tableStop(body: body, column: column, after: numbers.first?.top ?? headerTop)
            let tableEnd = stop ?? Double.infinity
            if stop != nil { isActive = false }
            let rowStarts = numbers.filter { $0.top < tableEnd }

            let bounds = rowStarts.map { $0.top - 2 }
            var segments: [(number: Int?, from: Double, to: Double)] = [(nil, headerTop, bounds.first ?? tableEnd)]
            for (index, start) in rowStarts.enumerated() {
                let next = index + 1 < bounds.count ? bounds[index + 1] : tableEnd
                segments.append((Int(start.text), bounds[index], next))
            }

            for segment in segments {
                let words = body.filter { $0.top >= segment.from && $0.top < segment.to && column($0) > 0 }
                let emptyCell: [[ImportWord]] = [[]]
                if let number = segment.number {
                    rows.append(Row(number: number, cells: Array(repeating: emptyCell, count: columnCount)))
                } else if rows.isEmpty {
                    continue
                } else {
                    // The row started on the previous page: its next chunk begins here.
                    for index in 0..<columnCount { rows[rows.count - 1].cells[index].append([]) }
                }
                let last = rows.count - 1
                for word in words {
                    let target = column(word)
                    rows[last].cells[target][rows[last].cells[target].count - 1].append(word)
                }
            }
        }

        guard sawHeader else { return nil }
        var sources = rows.compactMap(makeSource)
        // "Suggested Reading Order": numbered entries that point at table rows with "[n]".
        let order = readingOrder(in: pages)
        for index in sources.indices {
            guard let number = sources[index].number, let entry = order[number] else { continue }
            sources[index].readingOrder = entry.position
            sources[index].readingReason = entry.reason
        }
        return sources
    }

    /// Row number -> (position, reason), from lines like "2. [6] Title — why it comes here".
    static func readingOrder(in pages: [ImportPage]) -> [Int: (position: Int, reason: String)] {
        var texts: [String] = []
        var entryX: Double?
        scan: for page in pages {
            for line in TableLayout.lines(TableLayout.removingFooter(page.words)) {
                let text = line.map(\.text).joined(separator: " ")
                if entryX == nil {
                    guard text.range(of: #"^\d{1,3}\.\s*\[\d+\]"#, options: .regularExpression) != nil else { continue }
                    entryX = line[0].x0
                } else if let entryX, line[0].x0 < entryX - 5 {
                    break scan  // text back at the left margin ends the list
                }
                texts.append(text)
            }
        }
        let joined = texts.joined(separator: " ")
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,3})\.\s*\[(\d+)\]\s*"#) else { return [:] }
        let whole = NSRange(joined.startIndex..., in: joined)
        let matches = regex.matches(in: joined, range: whole)
        var result: [Int: (position: Int, reason: String)] = [:]
        for (index, match) in matches.enumerated() {
            guard let position = Int(joined[Range(match.range(at: 1), in: joined)!]),
                  let row = Int(joined[Range(match.range(at: 2), in: joined)!]) else { continue }
            let end = index + 1 < matches.count ? matches[index + 1].range.location : whole.length
            let body = (joined as NSString).substring(with: NSRange(location: match.range.upperBound, length: end - match.range.upperBound))
            let reason = body.components(separatedBy: " — ").dropFirst().joined(separator: " — ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            result[row] = (position, reason)
        }
        return result
    }

    // MARK: Private

    private static func tableStop(body: [ImportWord], column: (ImportWord) -> Int, after top: Double) -> Double? {
        body.filter { column($0) == 0 && Int($0.text) == nil && $0.top > top }.map(\.top).min()
    }

    private static func columnStarts(_ header: [ImportWord]) -> [Double]? {
        let names = ["#", "Period", "Source", "Link", "Classificati", "Triage"]
        let starts = names.compactMap { TableLayout.start(of: $0, in: header) }
        return starts.count == names.count ? starts : nil
    }

    private static func makeSource(_ row: Row) -> ImportedSource? {
        let phase = TableLayout.text(of: row.cells[1])
        let sourceText = TableLayout.text(of: row.cells[2])
        let linkText = TableLayout.text(of: row.cells[3], joiner: "")
        let classText = TableLayout.text(of: row.cells[4], joiner: "").uppercased().replacingOccurrences(of: " ", with: "")
        let note = TableLayout.text(of: row.cells[5])

        let parts = splitSource(sourceText)
        guard !parts.title.isEmpty else { return nil }
        return ImportedSource(
            title: parts.title,
            venue: parts.venue,
            year: parts.year,
            phase: phase,
            classification: classification(from: classText),
            triageNote: note,
            url: siteURL(from: linkText),
            linkAsShown: linkText,
            number: row.number
        )
    }

    /// "Title (2021) (Venue / Publisher)" becomes title, venue and year.
    static func splitSource(_ text: String) -> (title: String, venue: String, year: Int?) {
        guard let venuePart = ImportText.trailingParenthetical(in: text) else {
            return (text, "", ImportText.years(in: text).last)
        }
        var title = venuePart.rest
        var year = ImportText.years(in: venuePart.inner).last
        if let yearPart = ImportText.trailingParenthetical(in: title),
           yearPart.inner.count <= 25,
           let found = ImportText.years(in: yearPart.inner).last {
            title = yearPart.rest
            year = year ?? found
        }
        return (title.isEmpty ? text : title, venuePart.inner, year)
    }

    /// Triage tables show "site › shortened-path". Only the site can be trusted.
    static func siteURL(from linkText: String) -> URL? {
        let first = linkText.split(separator: "›", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? linkText
        let domain = first.replacingOccurrences(of: " ", with: "").lowercased()
        guard domain.range(of: #"^[a-z0-9.-]+\.[a-z]{2,}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://" + domain)
    }

    private static func classification(from text: String) -> Classification? {
        if text.hasPrefix("ESSENTIAL") { return .essential }
        if text.hasPrefix("COMPLEMEN") { return .complementary }
        if text.hasPrefix("SECONDARY") { return .secondary }
        return nil
    }
}
