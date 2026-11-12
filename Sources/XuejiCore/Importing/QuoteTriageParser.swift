import Foundation

/// What a quote triage report holds: the counts per document, the classified quotes, the timeline and the findings.
public struct ImportedQuoteTriage: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable { case essential, supporting, counter }

    public struct Document: Equatable, Sendable {
        public var title: String
        public var date: String
        public var words: Int
        public var term: Int
        public var modifier: Int
        public var usage: String
    }

    public struct Quote: Equatable, Sendable {
        public var text: String
        /// The lines of the "speaker / locator" cell, as they were laid out.
        public var originLines: [String]
        public var kind: Kind
        public var why: String
    }

    public struct Event: Equatable, Sendable {
        public var date: String
        public var event: String
        public var who: String
        public var frame: String
        /// A document that was missing from the corpus (its count cell shows a dash).
        public var isGap: Bool
    }

    public var title = ""
    public var term = ""
    /// The phrase counted apart from the term ("national" for "national security").
    public var modifier = ""
    public var corpusNote = ""
    public var caution = ""
    public var findings: [String] = []
    public var documents: [Document] = []
    public var quotes: [Quote] = []
    public var events: [Event] = []

    public init() {}
}

/// Reads a quote triage report (counts table, quotes table, timeline and recap), in English or Chinese.
enum QuoteTriageParser {
    private enum Table { case counts, quotes, timeline }
    private enum Bucket { case front, table(Table), caution, discard, findings }

    private static let lineGap = 3.5
    private static let cellGap = 8.0

    private struct Layout {
        var starts: [Double]
        /// What each column holds, in the same order as `starts`.
        var roles: [String]
        var headerWords: [ImportWord]
    }

    /// `nil` when the pages do not hold at least two of the report's three tables.
    static func parse(_ pages: [ImportPage]) -> ImportedQuoteTriage? {
        var layouts: [Table: Layout] = [:]
        var bodies: [Table: [(line: [ImportWord], firstOnPage: Bool)]] = [:]
        var front: [[ImportWord]] = []
        var caution: [[ImportWord]] = []
        var findings: [[ImportWord]] = []
        var bucket = Bucket.front

        for page in pages {
            let lines = TableLayout.lines(TableLayout.removingFooter(page.words))
            var firstOnPage = true
            var index = 0
            while index < lines.count {
                let line = lines[index]
                if let table = headerTable(of: line) {
                    var header = line
                    index += 1
                    while index < lines.count, isHeaderContinuation(lines[index], after: lines[index - 1], table: table, header: line) {
                        header += lines[index]
                        index += 1
                    }
                    if layouts[table] == nil, let layout = makeLayout(table, header: header) { layouts[table] = layout }
                    bucket = .table(table)
                    firstOnPage = true
                    continue
                }
                defer { index += 1 }

                if case .findings = bucket {
                    if isMethod(line) { bucket = .discard } else { findings.append(line) }
                    continue
                }
                if let number = headingNumber(of: line) {
                    let text = line.map(\.text).joined(separator: " ").lowercased()
                    let isRecap = number == 4 && (text.contains("recap") || text.contains("小结"))
                    bucket = isRecap ? .findings : .discard
                    continue
                }
                switch bucket {
                case .front:
                    front.append(line)
                case .caution:
                    caution.append(line)
                case .discard, .findings:
                    break
                case .table(let table):
                    guard let layout = layouts[table] else { continue }
                    if belongs(line, to: table, layout: layout) {
                        bodies[table, default: []].append((line, firstOnPage))
                        firstOnPage = false
                    } else {
                        bucket = table == .counts ? .caution : .discard
                        if table == .counts { caution.append(line) }
                    }
                }
            }
        }

        guard layouts.count >= 2 else { return nil }
        var result = ImportedQuoteTriage()
        readFront(front, into: &result)
        result.caution = text(of: caution)
        result.findings = readFindings(findings)
        if let layout = layouts[.counts] {
            result.modifier = modifier(from: layout, term: result.term)
            result.documents = readDocuments(bodies[.counts] ?? [], layout: layout)
        }
        if let layout = layouts[.quotes] { result.quotes = readQuotes(bodies[.quotes] ?? [], layout: layout) }
        if let layout = layouts[.timeline] { result.events = readEvents(bodies[.timeline] ?? [], layout: layout) }
        return result
    }

    // MARK: Headers

    private static func headerTable(of line: [ImportWord]) -> Table? {
        func has(_ prefixes: [String]) -> Bool {
            prefixes.allSatisfy { prefix in line.contains { $0.text.hasPrefix(prefix) } }
        }
        if has(["#", "Quote", "Class", "Why"]) || has(["#", "引文", "类别", "意义"]) { return .quotes }
        if has(["#", "Document", "Words", "How"]) || has(["#", "文件", "词数", "该词"]) { return .counts }
        if has(["Date", "Event", "Who", "What"]) || has(["日期", "事件", "发言方", "框架"]) { return .timeline }
        return nil
    }

    /// The lines under a heading line that are still part of the heading: tight against it and empty in the first column.
    private static func isHeaderContinuation(
        _ line: [ImportWord], after previous: [ImportWord], table: Table, header: [ImportWord]
    ) -> Bool {
        guard let first = line.first, let left = header.first?.x0 else { return false }
        let gap = (line.map(\.top).min() ?? 0) - (previous.map(\.bottom).max() ?? 0)
        guard gap < lineGap else { return false }
        // A numbered row starts with its number in the first column.
        if table != .timeline, first.x0 < left + 6, Int(first.text) != nil { return false }
        // The timeline's first row starts with a date in the first column.
        if table == .timeline, first.x0 < left + 6 { return false }
        return true
    }

    private static func makeLayout(_ table: Table, header: [ImportWord]) -> Layout? {
        let sorted = header.sorted { $0.x0 < $1.x0 }
        func start(_ prefixes: [String], after minimum: Double = -Double.infinity) -> Double? {
            sorted.first { word in word.x0 > minimum && prefixes.contains { word.text.hasPrefix($0) } }?.x0
        }
        func add(_ role: String, _ x: Double?, into list: inout [(String, Double)]) {
            if let x { list.append((role, x)) }
        }
        var columns: [(String, Double)] = []
        switch table {
        case .counts:
            guard let number = start(["#"]), let document = start(["Document", "文件"]), let words = start(["Words", "词数"]),
                  let per = start(["per", "每千词"], after: words), let usage = start(["How", "该词"], after: per) else { return nil }
            add("number", number, into: &columns)
            add("document", document, into: &columns)
            add("date", start(["Date", "日期"], after: document), into: &columns)
            add("words", words, into: &columns)
            let termStart = sorted.first { $0.x0 > words + 8 && $0.x0 < per - 8 }?.x0
            add("term", termStart, into: &columns)
            add("per", per, into: &columns)
            add("modifier", start(["of", "其中"], after: per + 8).flatMap { $0 < usage - 8 ? $0 : nil }, into: &columns)
            add("usage", usage, into: &columns)
        case .quotes:
            guard let number = start(["#"]), let quote = start(["Quote", "引文"]),
                  let origin = start(["Speaker", "发言人"]), let kind = start(["Class", "类别"]),
                  let why = start(["Why", "意义"]) else { return nil }
            columns = [("number", number), ("quote", quote), ("origin", origin), ("kind", kind), ("why", why)]
        case .timeline:
            guard let date = start(["Date", "日期"]), let event = start(["Event", "事件"]),
                  let who = start(["Who", "发言方"]), let frame = start(["What", "框架"]) else { return nil }
            columns = [("date", date), ("event", event), ("who", who), ("frame", frame)]
            let count = sorted.first { word in
                word.x0 > frame + 60 && (word.text.hasPrefix("“") || word.text.hasPrefix("\"") || word.text.hasPrefix("‘"))
            }?.x0
            add("count", count, into: &columns)
        }
        columns.sort { $0.1 < $1.1 }
        return Layout(starts: columns.map(\.1), roles: columns.map(\.0), headerWords: header)
    }

    // MARK: Body

    private static func headingNumber(of line: [ImportWord]) -> Int? {
        guard line.count >= 2, let first = line.first, first.text.hasSuffix("."),
              let number = Int(first.text.dropLast()), (1...4).contains(number) else { return nil }
        return number
    }

    private static func isMethod(_ line: [ImportWord]) -> Bool {
        guard let first = line.first?.text else { return false }
        return first.hasPrefix("Method") || first.hasPrefix("方法")
    }

    private static func belongs(_ line: [ImportWord], to table: Table, layout: Layout) -> Bool {
        guard let first = line.first, let left = layout.starts.first else { return false }
        let inFirstColumn = first.x0 < left + 6 && (table == .timeline ? true : layout.starts.count > 1 && first.x0 < layout.starts[1] - 6)
        switch table {
        case .counts, .quotes:
            // Every line of a row either starts with the row number or sits in a later column.
            return !inFirstColumn || Int(first.text) != nil
        case .timeline:
            guard inFirstColumn else { return true }
            return !isParagraph(line)
        }
    }

    /// A running line of text across the page, as opposed to cells that are far apart.
    private static func isParagraph(_ line: [ImportWord]) -> Bool {
        guard line.count >= 5 else { return false }
        for (left, right) in zip(line, line.dropFirst()) where right.x0 - left.x1 > cellGap { return false }
        return true
    }

    private static func column(_ word: ImportWord, _ layout: Layout) -> String {
        layout.roles[TableLayout.columnIndex(of: word.x0, starts: layout.starts)]
    }

    private static func cells(_ rows: [[ImportWord]], layout: Layout) -> [String: [ImportWord]] {
        var result: [String: [ImportWord]] = [:]
        for word in rows.flatMap({ $0 }) { result[column(word, layout), default: []].append(word) }
        return result
    }

    private static func text(of lines: [[ImportWord]]) -> String {
        TableLayout.text(of: [lines.flatMap { $0 }])
    }

    private static func cellText(_ words: [ImportWord]?) -> String {
        TableLayout.text(of: [words ?? []])
    }

    /// Rows that start with their number.
    private static func numberedRows(_ body: [(line: [ImportWord], firstOnPage: Bool)]) -> [[[ImportWord]]] {
        var rows: [[[ImportWord]]] = []
        for (line, _) in body {
            if let first = line.first, Int(first.text) != nil { rows.append([]) }
            if !rows.isEmpty { rows[rows.count - 1].append(line) }
        }
        return rows
    }

    private static func number(_ text: String) -> Int {
        Int(text.filter(\.isNumber)) ?? 0
    }

    private static func readDocuments(_ body: [(line: [ImportWord], firstOnPage: Bool)], layout: Layout) -> [ImportedQuoteTriage.Document] {
        numberedRows(body).compactMap { rows in
            let cell = cells(rows, layout: layout)
            let title = cellText(cell["document"])
            guard !title.isEmpty else { return nil }
            return ImportedQuoteTriage.Document(
                title: title, date: cellText(cell["date"]), words: number(cellText(cell["words"])),
                term: number(cellText(cell["term"])), modifier: number(cellText(cell["modifier"])),
                usage: cellText(cell["usage"])
            )
        }
    }

    private static func readQuotes(_ body: [(line: [ImportWord], firstOnPage: Bool)], layout: Layout) -> [ImportedQuoteTriage.Quote] {
        numberedRows(body).compactMap { rows in
            let cell = cells(rows, layout: layout)
            var quote = cellText(cell["quote"])
            guard !quote.isEmpty else { return nil }
            if quote.hasPrefix("“"), quote.hasSuffix("”"), quote.count >= 2 { quote = String(quote.dropFirst().dropLast()) }
            let originLines = TableLayout.lines(cell["origin"] ?? []).map { line in
                line.map(\.text).joined(separator: " ")
            }
            return ImportedQuoteTriage.Quote(
                text: quote, originLines: originLines, kind: kind(of: cellText(cell["kind"])), why: cellText(cell["why"])
            )
        }
    }

    private static func kind(of text: String) -> ImportedQuoteTriage.Kind {
        let compact = text.lowercased().filter { !$0.isWhitespace }
        if compact.contains("counter") || compact.contains("反证") { return .counter }
        if compact.contains("support") || compact.contains("支撑") { return .supporting }
        return .essential
    }

    private static func readEvents(_ body: [(line: [ImportWord], firstOnPage: Bool)], layout: Layout) -> [ImportedQuoteTriage.Event] {
        var rows: [[[ImportWord]]] = []
        var previous: [ImportWord]?
        for (line, firstOnPage) in body {
            let top = line.map(\.top).min() ?? 0
            let startsRow: Bool
            if let previous, !firstOnPage {
                startsRow = top - (previous.map(\.bottom).max() ?? 0) > lineGap
            } else {
                // At the top of a page the row goes on when the date column is empty.
                startsRow = rows.isEmpty || (line.first.map { $0.x0 < (layout.starts.first ?? 0) + 6 } ?? true)
            }
            if startsRow { rows.append([]) }
            rows[rows.count - 1].append(line)
            previous = line
        }
        return rows.compactMap { lines in
            let cell = cells(lines, layout: layout)
            let event = cellText(cell["event"]), date = cellText(cell["date"])
            guard !event.isEmpty || !date.isEmpty else { return nil }
            let count = cellText(cell["count"])
            return ImportedQuoteTriage.Event(
                date: date, event: event, who: cellText(cell["who"]), frame: cellText(cell["frame"]),
                isGap: count == "—" || count == "–" || count == "-"
            )
        }
    }

    // MARK: Text around the tables

    private static func readFront(_ lines: [[ImportWord]], into result: inout ImportedQuoteTriage) {
        guard let first = lines.first else { return }
        result.title = first.map(\.text).joined(separator: " ")
        var subtitle: [[ImportWord]] = []
        var note: [[ImportWord]] = []
        var previous = first
        var inNote = false
        for line in lines.dropFirst() {
            let gap = (line.map(\.top).min() ?? 0) - (previous.map(\.bottom).max() ?? 0)
            if gap > lineGap && !subtitle.isEmpty { inNote = true }
            if inNote { note.append(line) } else { subtitle.append(line) }
            previous = line
        }
        let subtitleText = text(of: subtitle)
        if let groups = ImportText.captures(#"Search term:\s*(.+?)\s*\("#, in: subtitleText)
            ?? ImportText.captures(#"检索词[：:]\s*(.+?)\s*[（(]"#, in: subtitleText) {
            result.term = groups[0].trimmingCharacters(in: .whitespaces)
        }
        result.corpusNote = text(of: note)
    }

    /// The phrase of the "of which “national security”" heading, without the term itself.
    private static func modifier(from layout: Layout, term: String) -> String {
        guard let index = layout.roles.firstIndex(of: "modifier") else { return "" }
        let start = layout.starts[index]
        let end = index + 1 < layout.starts.count ? layout.starts[index + 1] : Double.infinity
        let words = layout.headerWords.filter { $0.x0 >= start - 2.5 && $0.x0 < end - 2.5 }
        let text = TableLayout.text(of: [words])
        guard let groups = ImportText.captures(#"[“"](.+?)[”"]"#, in: text) else { return "" }
        var phrase = groups[0].trimmingCharacters(in: .whitespaces)
        if !term.isEmpty, phrase.lowercased().hasSuffix(term.lowercased()) {
            phrase = String(phrase.dropLast(term.count)).trimmingCharacters(in: .whitespaces)
        }
        return phrase
    }

    private static func readFindings(_ lines: [[ImportWord]]) -> [String] {
        var items: [String] = []
        for line in lines {
            let text = line.map(\.text).joined(separator: " ")
            if let groups = ImportText.captures(#"^\d+[.)]\s*(.*)$"#, in: text) {
                items.append(groups[0])
            } else if !items.isEmpty {
                items[items.count - 1] += " " + text
            }
        }
        return items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

extension ImportedQuoteTriage {
    /// Reads a PDF as a quote triage report, or `nil` when it is not one.
    public static func parse(_ pages: [ImportPage]) -> ImportedQuoteTriage? {
        QuoteTriageParser.parse(pages)
    }
}
