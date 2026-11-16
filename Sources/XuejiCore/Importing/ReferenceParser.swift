import Foundation

/// Reads one entry of a Harvard-style reference list:
/// "Authors (2020) 'Title', Venue, details. Available at: https://…" or "… DOI: 10.…".
enum ReferenceParser {
    static func parse(number: Int, text: String) -> ImportedReference {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var url: URL?
        var doi = ""

        if let groups = ImportText.captures(#"DOI:\s*(10\.\S+?)\.?(?:\s|$)"#, in: body) {
            doi = groups[0]
        }
        if let range = body.range(of: "Available at:") {
            url = webURL(String(body[range.upperBound...]))
        }
        if url == nil, !doi.isEmpty {
            url = URL(string: "https://doi.org/" + doi)
        }
        // Everything from the first marker on is the link, not the citation.
        let cuts = ["Available at:", "DOI:"].compactMap { body.range(of: $0)?.lowerBound }
        if let cut = cuts.min() { body = String(body[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let groups = ImportText.captures(#"^(.*?)\s*\((\d{4}[a-z]?|n\.d\.)\)\s*(.*)$"#, in: body) else {
            // Not Harvard: a footnote or national-standard style entry ("Author. “Title.” Journal, 2019, pp. 1-9").
            if let note = parseNote(number: number, text: text, hasLink: url != nil) {
                var result = note
                if result.url == nil { result.url = url }
                if result.doi.isEmpty { result.doi = doi }
                return result
            }
            return ImportedReference(number: number, title: String(body.prefix(140)), doi: doi, url: url)
        }
        // APA puts a full stop after the year; a series note such as "(No. 91)" is not part of the title.
        let rest = dropSeriesNote(groups[2]).trimmingCharacters(in: CharacterSet(charactersIn: ".,: "))
        let split = splitTitle(rest)
        let info = details(in: rest)
        // "Lynne Rienner Publishers.pp23–28" ends the publisher before the pages.
        var venue = split.venue.replacingOccurrences(
            of: #"[.,;]?\s*\bpp?\.?\s*\d[\d\s–—-]*\.?$"#, with: "", options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        var kind = ""
        if !info.volume.isEmpty || !info.issue.isEmpty {
            // The journal comes first; volume, issue and pages follow it.
            kind = "journalArticle"
            if let comma = venue.range(of: ", ") { venue = String(venue[..<comma.lowerBound]) }
        } else if rest.hasPrefix("‘") || rest.hasPrefix("'") {
            kind = "journalArticle"
        } else if !venue.isEmpty {
            kind = "book"
        } else if url != nil {
            kind = "webPage"
        }
        return ImportedReference(
            number: number,
            authors: normalizeAuthors(groups[0]),
            year: Int(groups[1].prefix(4)),
            title: split.title.isEmpty ? String(body.prefix(140)) : split.title,
            venue: venue,
            doi: doi,
            url: url,
            kind: kind,
            volume: info.volume,
            issue: info.issue,
            pages: info.pages
        )
    }

    /// A quoted title ends at the first closing quote that is followed by a comma, a full stop or nothing.
    /// An unquoted one runs up to the first full stop.
    static func splitTitle(_ rest: String) -> (title: String, venue: String) {
        let characters = Array(rest)
        if let first = characters.first, first == "‘" || first == "'" {
            for index in 1..<max(characters.count, 1) where characters[index] == "’" {
                let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
                if next == nil || next == "," || next == "." {
                    let title = String(characters[1..<index])
                    let venue = String(characters[(index + 1)...]).trimmingCharacters(in: CharacterSet(charactersIn: ",. "))
                    return (title, venue)
                }
            }
        }
        if let stop = rest.range(of: ". ") {
            let venue = rest[stop.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: ",. "))
            return (String(rest[..<stop.lowerBound]), venue)
        }
        return (rest.trimmingCharacters(in: CharacterSet(charactersIn: ". ")), "")
    }

    // MARK: Authors

    /// "Buzan, B., Wæver, O., & De Wilde, J." (APA) and "Buzan B, Wæver O" (Springer) become
    /// "Buzan, B.; Wæver, O.; De Wilde, J." so each person is read on their own. Anything else is left as it is.
    static func normalizeAuthors(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return raw }
        text = text.replacingOccurrences(of: "&", with: ",").replacingOccurrences(of: " and ", with: ", ")
        text = text.replacingOccurrences(of: #",\s*,"#, with: ",", options: .regularExpression)

        if let regex = try? NSRegularExpression(pattern: #"\s*([^,;.]+?),\s*((?:\p{Lu}\.\s*)+)"#) {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            if !matches.isEmpty {
                var leftover = text
                var people: [String] = []
                for match in matches.reversed() {
                    if let whole = Range(match.range, in: leftover) { leftover.removeSubrange(whole) }
                }
                for match in matches {
                    guard let family = Range(match.range(at: 1), in: text), let initials = Range(match.range(at: 2), in: text) else { continue }
                    people.append("\(text[family].trimmingCharacters(in: .whitespaces)), \(text[initials].trimmingCharacters(in: .whitespaces))")
                }
                if leftover.trimmingCharacters(in: CharacterSet(charactersIn: ", ;")).isEmpty { return people.joined(separator: "; ") }
            }
        }

        let tokens = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let springer = tokens.compactMap { ImportText.captures(#"^(.+?)\s+(\p{Lu}{1,4})$"#, in: $0) }
        if !tokens.isEmpty, springer.count == tokens.count {
            return springer.map { "\($0[0]), \($0[1])" }.joined(separator: "; ")
        }
        return raw
    }

    private static func dropSeriesNote(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s*\((?:No|Vol|Issue|Series)\.?\s*\d+\)"#, with: "", options: .regularExpression)
    }

    // MARK: Numbered lists

    /// "[3] text", "3. text" and "3.text" (also with a full-width stop or "、") start an entry.
    static func numberedStart(_ line: String) -> (number: Int, text: String)? {
        guard let groups = ImportText.captures(#"^\s*(?:\[(\d{1,3})\]|(\d{1,3})\s*[.．、])\s*(\S.*)$"#, in: line) else { return nil }
        guard let number = Int(groups[0].isEmpty ? groups[1] : groups[0]) else { return nil }
        return (number, groups[2])
    }

    /// The entries of a pasted list. When the lines are numbered, a line without a number continues the entry above.
    /// Without numbers, blank lines separate the entries; if there are none, every line is an entry.
    static func splitEntries(_ text: String) -> [(number: Int, text: String)] {
        let lines = text.components(separatedBy: .newlines)
        let filled = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var entries: [(number: Int, text: String)] = []
        if filled.contains(where: { numberedStart($0) != nil }) {
            for line in filled {
                if let start = numberedStart(line) {
                    entries.append(start)
                } else if !entries.isEmpty {
                    entries[entries.count - 1].text += " " + line.trimmingCharacters(in: .whitespaces)
                }
            }
            return entries
        }
        var groups: [[String]] = [[]]
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !(groups.last?.isEmpty ?? true) { groups.append([]) }
            } else {
                groups[groups.count - 1].append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        let blocks = groups.filter { !$0.isEmpty }
        // Blank lines separate entries only when they sit between two of them: a blank line at the end of the text
        // (a file's last line) must not glue a whole list into one entry.
        let pieces = blocks.count > 1 ? blocks.map { $0.joined(separator: " ") } : filled.map { $0.trimmingCharacters(in: .whitespaces) }
        return pieces.enumerated().map { ($0.offset + 1, $0.element) }
    }

    /// A pasted reference list, one entry at a time.
    static func parseList(_ text: String) -> [ImportedReference] {
        splitEntries(text).map { parse(number: $0.number, text: $0.text) }
    }

    // MARK: Volume, issue and pages

    /// "pp.1-45" → "1-45"; any kind of dash becomes a hyphen.
    private static func cleanPages(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\s*[-–—]\s*"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Volume, issue and pages written in the usual ways: "Vol.20, No.1, pp.1-45", "3(2), pp. 1-9", "第 7期，第 25-34 页".
    static func details(in text: String) -> (volume: String, issue: String, pages: String) {
        var volume = "", issue = "", pages = ""
        if let g = ImportText.captures(#"(?i)\bvol(?:ume)?\.?\s*(\d+)"#, in: text) { volume = g[0] }
        if let g = ImportText.captures(#"(?i)\b(?:no|issue)\.?\s*(\d+)"#, in: text) { issue = g[0] }
        if volume.isEmpty, issue.isEmpty, let g = ImportText.captures(#"\b(\d{1,4})\((\d{1,3})\)"#, in: text) {
            volume = g[0]
            issue = g[1]
        }
        if let g = ImportText.captures(#"(?i)\bpp?\.?\s*(\d+(?:\s*[-–—]\s*\d+)?)"#, in: text) { pages = cleanPages(g[0]) }
        if issue.isEmpty, let g = ImportText.captures(#"第\s*(\d+)\s*期"#, in: text) { issue = g[0] }
        if pages.isEmpty, let g = ImportText.captures(#"第\s*(\d+(?:\s*[-–—]\s*\d+)?)\s*页"#, in: text) { pages = cleanPages(g[0]) }
        return (volume, issue, pages)
    }

    /// "访问时间：2024 年 7 月 1 日" → "2024-07-01".
    private static func accessDate(in text: String) -> String {
        guard let g = ImportText.captures(#"访问时间[：:]\s*(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日"#, in: text),
              let y = Int(g[0]), let m = Int(g[1]), let d = Int(g[2]) else { return "" }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    // MARK: Footnote and national-standard styles

    private static func squash(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func parseNote(number: Int, text: String, hasLink: Bool) -> ImportedReference? {
        let body = squash(text)
        if body.contains("《") { return parseChinese(number: number, body: body) }
        if !hasLink, body.range(of: "http", options: .caseInsensitive) != nil, let page = parseWebPage(number: number, body: body) {
            return page
        }
        if body.contains("“") || body.contains("\"") || body.contains("‘") { return parseQuoted(number: number, body: body) }
        return parseBook(number: number, body: body)
    }

    private static let years = #"\b(?:19|20)\d{2}\b"#

    private static func lastYear(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: years) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.last.flatMap { Range($0.range, in: text) }.flatMap { Int(text[$0]) }
    }

    /// "胡仕胜，王珏：《标题》，载《期刊》，2020 年第 7期，第 25-34 页。" or "…：《书名》，出版社，2015 年版，第 3-34 页。"
    private static func parseChinese(number: Int, body: String) -> ImportedReference? {
        guard let groups = ImportText.captures(#"^(.+?)[：:]\s*《(.+?)》(.*)$"#, in: body) else { return nil }
        let authors = groups[0].split(whereSeparator: { "，,、".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "; ")
        let rest = groups[2]
        var venue = ""
        var kind = "book"
        if let journal = ImportText.captures(#"载\s*《(.+?)》"#, in: rest) {
            venue = journal[0]
            kind = "journalArticle"
        } else {
            let parts = rest.split(whereSeparator: { "，,".contains($0) }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " 。.")) }
            venue = parts.first { !$0.isEmpty && !$0.contains("年") && !$0.contains("页") } ?? ""
        }
        let year = ImportText.captures(#"((?:19|20)\d{2})\s*年"#, in: rest).flatMap { Int($0[0]) }
        let info = details(in: rest)
        return ImportedReference(
            number: number, authors: authors, year: year, title: groups[1], venue: venue,
            kind: kind, issue: info.issue, pages: info.pages
        )
    }

    /// "Organisation, Title, 2024-12-23, https://…, 访问时间：2024 年 12 月 23 日", and the quoted form
    /// `Author & Author, “Title,” Organisation, December 2021, https://…, 访问时间：…`.
    private static func parseWebPage(number: Int, body: String) -> ImportedReference? {
        guard let start = body.range(of: "http", options: .caseInsensitive) else { return nil }
        var tail = String(body[start.lowerBound...])
        for marker in ["访问时间", "Accessed", "accessed"] {
            if let cut = tail.range(of: marker) { tail = String(tail[..<cut.lowerBound]) }
        }
        // A link copied from a page can break across lines and pick up spaces.
        let link = tail.filter { !$0.isWhitespace }.trimmingCharacters(in: CharacterSet(charactersIn: ",，;。. "))
        guard let url = webURL(link) else { return nil }
        let head = String(body[..<start.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " ,，"))
        let accessed = accessDate(in: body)

        var authors = "", title = "", venue = "", dateText = ""
        if let quoted = ImportText.captures(#"^(.+?)[.,]?\s*[“"‘]\s*(.+?)[”"’](?=[,.\s]|$)\s*(.*)$"#, in: head) {
            authors = quoted[0].trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
            title = quoted[1].trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
            let after = quoted[2].split(whereSeparator: { ",，".contains($0) })
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }.filter { !$0.isEmpty }
            venue = after.first { lastYear(in: $0) == nil } ?? ""
            dateText = after.first { lastYear(in: $0) != nil } ?? ""
        } else {
            let parts = head.split(whereSeparator: { ",，".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !parts.isEmpty else { return nil }
            let date = parts.first { ImportText.captures(#"^\d{4}-\d{1,2}-\d{1,2}$"#, in: $0) != nil }
            dateText = date ?? ""
            let others = parts.filter { $0 != date }
            authors = others.count > 1 ? others[0] : ""
            title = others.count > 1 ? others.dropFirst().joined(separator: ", ") : (others.first ?? "")
        }
        guard !title.isEmpty else { return nil }
        return ImportedReference(
            number: number, authors: authors, year: lastYear(in: dateText), title: title, venue: venue, url: url,
            kind: "webPage", accessed: accessed, date: dateText
        )
    }

    /// `Author. “Title.” Journal, Vol. 20, No. 1, 2019, pp. 1-45`, the chapter form
    /// `Author. “Chapter.” Book. Publisher, 2022. pp. 135-145.` and the Chicago note
    /// `Author, ‘Chapter’, in Book, ed. Editor (City: Publisher, 1995), pp. 46–86.`
    private static func parseQuoted(number: Int, body: String) -> ImportedReference? {
        // A closing single quote counts only when it is followed by punctuation or a space ("Government’s" does not close).
        guard let groups = ImportText.captures(#"^(.+?)[.,]?\s*[“"‘]\s*(.+?)[”"’](?=[,.\s]|$)\s*(.*)$"#, in: body) else { return nil }
        let authors = groups[0].trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        let title = groups[1].trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        var rest = groups[2].trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        var hadIn = false
        if rest.lowercased().hasPrefix("in ") {
            rest = String(rest.dropFirst(3))
            hadIn = true
        }
        let comma = rest.range(of: ", ")
        let stop = rest.range(of: ". ")
        let firstStop = [comma?.lowerBound, stop?.lowerBound].compactMap { $0 }.min()
        let venue = (firstStop.map { String(rest[..<$0]) } ?? rest).trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        guard !authors.isEmpty, !title.isEmpty else { return nil }

        let info = details(in: rest)
        let journalLike = !info.volume.isEmpty || !info.issue.isEmpty
        var publisher = ""
        var kind = "journalArticle"
        if hadIn || (!journalLike && stop != nil && stop?.lowerBound == firstStop) {
            kind = "bookChapter"
            if let g = ImportText.captures(#"\(([^:()]+):\s*([^,()]+),"#, in: rest) {
                publisher = g[1].trimmingCharacters(in: .whitespaces)
            } else if let stop {
                let after = rest[stop.upperBound...]
                publisher = (after.range(of: ", ").map { String(after[..<$0.lowerBound]) } ?? "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
            }
        }
        return ImportedReference(
            number: number, authors: authors, year: lastYear(in: rest), title: title, venue: venue,
            kind: kind, volume: info.volume, issue: info.issue, pages: info.pages, publisher: publisher
        )
    }

    /// The Chicago-note form with commas all the way: `Author, Title, Publisher, 1983, pp. 73–88;`.
    /// The author is what comes before the first comma and the publisher what comes after the last one;
    /// the title in between may have commas of its own.
    private static func parseCommaBook(number: Int, head: String, year: Int?, tail: String) -> ImportedReference? {
        let parts = head.components(separatedBy: ", ")
        guard parts.count >= 3 else { return nil }
        let trim = CharacterSet(charactersIn: " .,;")
        let authors = parts[0].trimmingCharacters(in: trim)
        let publisher = (parts.last ?? "").trimmingCharacters(in: trim)
        let title = parts[1..<(parts.count - 1)].joined(separator: ", ").trimmingCharacters(in: trim)
        guard !authors.isEmpty, !title.isEmpty, !publisher.isEmpty else { return nil }
        let info = details(in: tail)
        return ImportedReference(
            number: number, authors: authors, year: year, title: title, venue: publisher, kind: "book", pages: info.pages
        )
    }

    /// `Author. Title: subtitle. Publisher, 1996. pp. 11-13.`
    private static func parseBook(number: Int, body: String) -> ImportedReference? {
        guard let found = lastMatch(#",\s*((?:19|20)\d{2})\b"#, in: body) else { return nil }
        let head = String(body[..<found.start])
        let year = Int(found.year)
        // The authors end at the first full stop that does not close an initial ("Harsh V. Pant.").
        var cut: Range<String.Index>?
        var search = head.startIndex..<head.endIndex
        while let stop = head.range(of: ". ", range: search) {
            let before = head[..<stop.lowerBound]
            let isInitial = before.last?.isLetter == true && before.dropLast().last == " "
            if !isInitial { cut = stop; break }
            search = stop.upperBound..<head.endIndex
        }
        guard let authorsEnd = cut else { return parseCommaBook(number: number, head: head, year: year, tail: String(body[found.end...])) }
        let authors = String(head[..<authorsEnd.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        let rest = String(head[authorsEnd.upperBound...])
        guard let publisherStart = rest.range(of: ". ", options: .backwards) else { return nil }
        let title = String(rest[..<publisherStart.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        let publisher = String(rest[publisherStart.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        guard !authors.isEmpty, !title.isEmpty else { return nil }
        let info = details(in: String(body[found.end...]))
        return ImportedReference(
            number: number, authors: authors, year: year, title: title, venue: publisher, kind: "book", pages: info.pages
        )
    }

    private static func lastMatch(_ pattern: String, in text: String) -> (start: String.Index, end: String.Index, year: String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let whole = Range(match.range, in: text), let group = Range(match.range(at: 1), in: text) else { return nil }
        return (whole.lowerBound, whole.upperBound, String(text[group]))
    }

    private static func webURL(_ text: String) -> URL? {
        let clean = text.trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        guard let url = URL(string: clean), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
}
