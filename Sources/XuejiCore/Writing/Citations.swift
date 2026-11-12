import Foundation

/// How in-text citations and the bibliography are written.
public enum CitationStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Author–date, "(Silva, 2020, p. 12)".
    case harvard
    /// The Chinese national standard GB/T 7714, numbered in order of first citation: "[1]12".
    case gbt7714
    /// Author–date, "(Silva & Jones, 2020, p. 12)".
    case apa
    /// Brazilian standard, "(SILVA; JONES, 2020, p. 12)".
    case abnt
    /// Numbered in order of first citation, "[1, p. 12]".
    case ieee

    public var id: String { rawValue }
    public var isNumbered: Bool { self == .ieee || self == .gbt7714 }
}

public struct Person: Equatable, Sendable {
    public var family: String
    public var given: String
}

/// What is known about a source, taken from its card.
public struct Reference: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// As written on the card: "Silva, João; Jones, Karl" or "João Silva and Karl Jones".
    public var authors: String
    public var year: Int?
    public var title: String
    /// Journal, publisher or site.
    public var venue: String
    public var doi: String
    public var url: String
    /// The key of the card's "kind of source" (journalArticle, book, press…); may be empty.
    public var kind: String
    public var created: Date

    public init(
        id: UUID, authors: String = "", year: Int? = nil, title: String = "", venue: String = "",
        doi: String = "", url: String = "", kind: String = "", created: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.id = id
        self.authors = authors
        self.year = year
        self.title = title
        self.venue = venue
        self.doi = doi
        self.url = url
        self.kind = kind
        self.created = created
    }
}

public struct AuthorList: Equatable, Sendable {
    public var people: [Person]
    /// "et al." was written after the names.
    public var etAl: Bool
}

public enum Authors {
    /// Reads "Silva, João; Jones, Karl", "João Silva and Karl Jones", "Silva, J., Jones, K." and the like.
    /// Writing "Family, Given" separated by semicolons is always read exactly.
    public static func parse(_ text: String) -> AuthorList {
        var source = text
        var etAl = false
        if let range = source.range(of: #"\bet\s+al\b\.?"#, options: [.regularExpression, .caseInsensitive]) {
            etAl = true
            source = String(source[..<range.lowerBound])
        }
        var separated = false
        for word in [" and ", " & ", " e ", " y "] where source.contains(word) {
            source = source.replacingOccurrences(of: word, with: ";")
            separated = true
        }
        if source.contains(";") || source.contains("\n") { separated = true }
        source = source.replacingOccurrences(of: "\n", with: ";")

        var people: [Person] = []
        if separated {
            for part in source.split(separator: ";") {
                if let person = makePerson(from: String(part)) { people.append(person) }
            }
        } else {
            let tokens = source.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if tokens.count == 2 {
                people.append(Person(family: tokens[0], given: tokens[1]))
            } else if tokens.count >= 4 && tokens.count % 2 == 0 {
                for index in stride(from: 0, to: tokens.count, by: 2) {
                    people.append(Person(family: tokens[index], given: tokens[index + 1]))
                }
            } else {
                for token in tokens { if let person = makePerson(from: token) { people.append(person) } }
            }
        }
        return AuthorList(people: people, etAl: etAl)
    }

    private static func makePerson(from raw: String) -> Person? {
        let text = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        guard !text.isEmpty else { return nil }
        if let comma = text.firstIndex(of: ",") {
            let family = text[..<comma].trimmingCharacters(in: .whitespaces)
            let given = text[text.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            return Person(family: family, given: given)
        }
        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1, let last = words.last else { return Person(family: text, given: "") }
        return Person(family: last, given: words.dropLast().joined(separator: " "))
    }

    /// "João Pedro" → "J. P."; "J." stays "J.".
    public static func initials(_ given: String) -> String {
        given.split(whereSeparator: { $0 == " " || $0 == "-" })
            .compactMap { token -> String? in
                guard let first = token.first else { return nil }
                return String(first).uppercased() + "."
            }
            .joined(separator: " ")
    }
}

public struct BibliographyEntry: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// The position in a numbered style; nil in the author–date styles.
    public var number: Int?
    /// The reference as it is printed (numbered styles already start with "[1] ").
    public var text: String
}

public struct IncompleteReference: Equatable, Sendable {
    public let id: UUID
    /// "authors", "year", "title".
    public var missing: [String]
}

public struct CitationOutput: Equatable, Sendable {
    /// The input texts with every `[@key]` turned into an in-text citation.
    public var texts: [String]
    public var bibliography: [BibliographyEntry]
    /// Keys written in the text that match no source.
    public var unknownKeys: [String]
    public var incomplete: [IncompleteReference]
}

public enum Citations {
    // MARK: Keys and markers

    /// A short name for each source ("Silva2020"), the same on every call while the sources do not change:
    /// the earliest card keeps the plain name, later ones with the same name get "b", "c"…
    public static func keys(for references: [Reference]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        var used: [String: Int] = [:]
        for reference in ordered(references) {
            let base = baseKey(of: reference)
            let count = used[base, default: 0]
            used[base] = count + 1
            result[reference.id] = base + suffix(count)
        }
        return result
    }

    /// "[@Silva2020]" or "[@Silva2020, p. 12]".
    public static func marker(key: String, page: String? = nil) -> String {
        let clean = page?.trimmingCharacters(in: .whitespaces) ?? ""
        return clean.isEmpty ? "[@\(key)]" : "[@\(key), \(clean)]"
    }

    private static func baseKey(of reference: Reference) -> String {
        let list = Authors.parse(reference.authors)
        var name = list.people.first?.family ?? ""
        if name.isEmpty { name = reference.title.split(separator: " ").first.map(String.init) ?? "" }
        let folded = name.folding(options: .diacriticInsensitive, locale: nil)
        var word = String(folded.filter { $0.isLetter || $0.isNumber }.prefix(24))
        if word.isEmpty { word = "Source" }
        word = word.prefix(1).uppercased() + word.dropFirst()
        return word + (reference.year.map(String.init) ?? "nd")
    }

    private static func suffix(_ count: Int) -> String {
        if count == 0 { return "" }
        if count <= 25 { return String(Character(UnicodeScalar(UInt8(97 + count)))) }
        return "-\(count + 1)"
    }

    private static let markerPattern = try! NSRegularExpression(
        pattern: #"\[@([\p{L}\p{N}_\-]+)(?:\s*,\s*([^\]\n]+))?\]"#
    )

    private static func ordered(_ references: [Reference]) -> [Reference] {
        references.sorted {
            $0.created != $1.created ? $0.created < $1.created : $0.id.uuidString < $1.id.uuidString
        }
    }

    // MARK: Processing

    /// Replaces the markers in `texts` with in-text citations and builds the bibliography.
    /// - Parameters:
    ///   - linked: sources the texts are based on, in order; they are listed too when `includeUncited` is on.
    ///   - references: every source that can be cited.
    public static func process(
        texts: [String], linked: [UUID], references: [Reference], style: CitationStyle, includeUncited: Bool
    ) -> CitationOutput {
        let sorted = ordered(references)
        let keysByID = keys(for: sorted)
        var idByKey: [String: UUID] = [:]
        for (id, key) in keysByID { idByKey[key.lowercased()] = id }
        let byID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0) })
        let canonical = canonicalIDs(sorted)

        // 1. What is cited, in order of first appearance.
        var cited: [UUID] = []
        var unknown: [String] = []
        for text in texts {
            for match in markerMatches(in: text) {
                if let id = idByKey[match.key.lowercased()], let main = canonical[id] {
                    if !cited.contains(main) { cited.append(main) }
                } else if !unknown.contains(match.key) {
                    unknown.append(match.key)
                }
            }
        }
        var listed = cited
        if includeUncited {
            for id in linked {
                if let main = canonical[id], byID[main] != nil, !listed.contains(main) { listed.append(main) }
            }
        }

        // 2. Order, numbers and "2020a" letters.
        var numbers: [UUID: Int] = [:]
        var letters: [UUID: String] = [:]
        if style.isNumbered {
            for (index, id) in listed.enumerated() { numbers[id] = index + 1 }
        } else {
            listed.sort { sortKey(byID[$0]!) < sortKey(byID[$1]!) }
            var groups: [String: [UUID]] = [:]
            for id in listed { groups[groupKey(byID[id]!), default: []].append(id) }
            for (_, ids) in groups where ids.count > 1 {
                let byTitle = ids.sorted { byID[$0]!.title.localizedCaseInsensitiveCompare(byID[$1]!.title) == .orderedAscending }
                for (index, id) in byTitle.enumerated() where index < 26 {
                    letters[id] = String(Character(UnicodeScalar(UInt8(97 + index))))
                }
            }
        }

        // 3. The texts.
        var outputTexts: [String] = []
        for text in texts {
            let source = text as NSString
            var result = ""
            var cursor = 0
            for match in markerMatches(in: text) {
                result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                if let id = idByKey[match.key.lowercased()], let main = canonical[id], let reference = byID[main] {
                    result += inText(
                        reference, style: style, letter: letters[main] ?? "", number: numbers[main], page: match.page
                    )
                } else {
                    result += source.substring(with: match.range)
                }
                cursor = match.range.location + match.range.length
            }
            result += source.substring(from: cursor)
            outputTexts.append(result)
        }

        // 4. The bibliography.
        var entries: [BibliographyEntry] = []
        var incomplete: [IncompleteReference] = []
        for id in listed {
            guard let reference = byID[id] else { continue }
            let body = entry(reference, style: style, letter: letters[id] ?? "")
            let number = numbers[id]
            entries.append(BibliographyEntry(
                id: id, number: number, text: number.map { "[\($0)] " + body } ?? body
            ))
            var missing: [String] = []
            if Authors.parse(reference.authors).people.isEmpty { missing.append("authors") }
            if reference.year == nil { missing.append("year") }
            if reference.title.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("title") }
            if !missing.isEmpty { incomplete.append(IncompleteReference(id: id, missing: missing)) }
        }
        return CitationOutput(texts: outputTexts, bibliography: entries, unknownKeys: unknown, incomplete: incomplete)
    }

    private struct MarkerMatch {
        let range: NSRange
        let key: String
        let page: String?
    }

    private static func markerMatches(in text: String) -> [MarkerMatch] {
        let source = text as NSString
        return markerPattern.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            let page = match.range(at: 2).location == NSNotFound ? nil : source.substring(with: match.range(at: 2))
            return MarkerMatch(range: match.range, key: source.substring(with: match.range(at: 1)), page: page)
        }
    }

    // MARK: Duplicates

    /// Maps every source to the first card that is the same work (same DOI, same address, or same title,
    /// year and first author), so a work imported twice is cited and listed once.
    private static func canonicalIDs(_ sorted: [Reference]) -> [UUID: UUID] {
        var first: [String: UUID] = [:]
        var result: [UUID: UUID] = [:]
        for reference in sorted {
            let identities = identityKeys(of: reference)
            let known = identities.compactMap { first[$0] }.first
            let main = known ?? reference.id
            for identity in identities where first[identity] == nil { first[identity] = main }
            result[reference.id] = main
        }
        return result
    }

    private static func identityKeys(of reference: Reference) -> [String] {
        var keys: [String] = []
        let doi = normalizedDOI(reference.doi)
        if !doi.isEmpty { keys.append("doi:" + doi.lowercased()) }
        let url = reference.url.lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !url.isEmpty, !url.hasPrefix("file:") { keys.append("url:" + url) }
        let title = fold(reference.title)
        if !title.isEmpty {
            keys.append("work:\(title)|\(reference.year.map(String.init) ?? "")|\(fold(Authors.parse(reference.authors).people.first?.family ?? ""))")
        }
        return keys
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    static func normalizedDOI(_ doi: String) -> String {
        var text = doi.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://doi.org/", "http://doi.org/", "https://dx.doi.org/", "http://dx.doi.org/", "doi:"] {
            if text.lowercased().hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func link(of reference: Reference) -> String {
        let doi = normalizedDOI(reference.doi)
        if !doi.isEmpty { return "https://doi.org/" + doi }
        return reference.url.hasPrefix("file:") ? "" : reference.url
    }

    // MARK: Sorting

    private static func sortKey(_ reference: Reference) -> String {
        let list = Authors.parse(reference.authors)
        let authors = list.people.isEmpty
            ? fold(reference.title)
            : list.people.map { fold($0.family) + fold($0.given) }.joined(separator: "|")
        return authors + "#" + String(format: "%05d", reference.year ?? 0) + "#" + fold(reference.title)
    }

    /// Sources that print the same author(s) and year (they get 2020a, 2020b).
    private static func groupKey(_ reference: Reference) -> String {
        let list = Authors.parse(reference.authors)
        let authors = list.people.isEmpty
            ? fold(reference.title)
            : list.people.map { fold($0.family) }.joined(separator: "|")
        return authors + "#" + (reference.year.map(String.init) ?? "")
    }

    // MARK: Writing

    private static func yearText(_ reference: Reference, letter: String, style: CitationStyle) -> String {
        guard let year = reference.year else { return style == .abnt ? "[s.d.]" : "n.d." }
        return String(year) + letter
    }

    /// "12" → "p. 12", "12-14" → "pp. 12-14"; anything else as it was written.
    static func pageText(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.hasPrefix("p.") || lower.hasPrefix("pp.") || lower.hasPrefix("p ") || lower.hasPrefix("pp ") { return raw }
        if raw.allSatisfy({ $0.isNumber || "-–—, ".contains($0) }) {
            return (raw.contains("-") || raw.contains("–") || raw.contains("—") ? "pp. " : "p. ") + raw
        }
        return raw
    }

    /// GB/T 7714 puts the page right after the bracket, as a plain number: "[2]260".
    private static func gbPage(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        for prefix in ["pp.", "p.", "pp ", "p "] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        text = text.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func isCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    /// The document-type letter GB/T 7714 puts after the title.
    private static func gbCode(_ kind: String) -> String {
        switch kind {
        case "journalArticle": return "J"
        case "book": return "M"
        case "thinkTankReport", "governmentDocument", "poll": return "R"
        case "press": return "N"
        case "webPage": return "EB/OL"
        default: return "Z"
        }
    }

    private static func shortTitle(_ title: String) -> String {
        let words = title.split(separator: " ")
        return words.prefix(4).joined(separator: " ") + (words.count > 4 ? "…" : "")
    }

    static func inText(
        _ reference: Reference, style: CitationStyle, letter: String, number: Int?, page rawPage: String?
    ) -> String {
        let page = pageText(rawPage)
        if style == .gbt7714 {
            return "[" + (number.map(String.init) ?? "?") + "]" + (gbPage(rawPage) ?? "")
        }
        if style.isNumbered {
            return "[" + (number.map(String.init) ?? "?") + (page.map { ", " + $0 } ?? "") + "]"
        }
        let list = Authors.parse(reference.authors)
        let families = list.people.map(\.family)
        let year = yearText(reference, letter: letter, style: style)
        var names: String
        switch style {
        case .harvard:
            if families.isEmpty { names = shortTitle(reference.title) }
            else if families.count > 3 || list.etAl { names = families[0] + " et al." }
            else { names = joined(families, last: " and ") }
        case .apa:
            if families.isEmpty { names = shortTitle(reference.title) }
            else if families.count >= 3 || list.etAl { names = families[0] + " et al." }
            else { names = families.joined(separator: " & ") }
        case .abnt:
            let upper = families.map { $0.uppercased() }
            if upper.isEmpty { names = shortTitle(reference.title).uppercased() }
            else if upper.count > 3 || list.etAl { names = upper[0] + " et al." }
            else { names = upper.joined(separator: "; ") }
        case .ieee, .gbt7714:
            names = ""
        }
        return "(" + names + ", " + year + (page.map { ", " + $0 } ?? "") + ")"
    }

    /// "A", "A and B", "A, B and C" (or with another word before the last name).
    private static func joined(_ items: [String], last word: String) -> String {
        guard items.count > 1, let tail = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + word + tail
    }

    private static func sentence(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = clean.last else { return "" }
        return ".?!…".contains(last) ? clean : clean + "."
    }

    private static func isArticle(_ reference: Reference) -> Bool {
        reference.kind == "journalArticle" || reference.kind == "press"
    }

    static func entry(_ reference: Reference, style: CitationStyle, letter: String) -> String {
        let list = Authors.parse(reference.authors)
        let people = list.people
        let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let venue = reference.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = link(of: reference)
        let year = yearText(reference, letter: letter, style: style)

        func familyInitials(_ person: Person) -> String {
            let initials = Authors.initials(person.given)
            return initials.isEmpty ? person.family : person.family + ", " + initials
        }

        switch style {
        case .harvard:
            let names: String
            if people.isEmpty { names = "" }
            else if people.count > 3 || list.etAl { names = familyInitials(people[0]) + " et al." }
            else { names = joined(people.map(familyInitials), last: " and ") }
            var text = names.isEmpty ? "" : names + " "
            text += "(\(year)) "
            if names.isEmpty {
                text = sentence(title) + " (\(year))"
                text += venue.isEmpty ? "" : " " + sentence(venue)
            } else if isArticle(reference) && !title.isEmpty {
                text += "'\(title)'" + (venue.isEmpty ? "." : ", " + sentence(venue))
            } else {
                text += sentence(title) + (venue.isEmpty ? "" : " " + sentence(venue))
            }
            if !address.isEmpty { text += " Available at: " + address + "." }
            return text
        case .apa:
            let names: String
            if people.isEmpty { names = "" }
            else {
                let all = people.map(familyInitials) + (list.etAl ? ["et al."] : [])
                names = all.count == 1 ? all[0] : all.dropLast().joined(separator: ", ") + ", & " + all[all.count - 1]
            }
            var text = ""
            if names.isEmpty {
                text = sentence(title) + " (\(year))."
            } else {
                text = sentence(names) + " (\(year)). " + sentence(title)
            }
            if !venue.isEmpty { text += " " + sentence(venue) }
            if !address.isEmpty { text += " " + address }
            return text
        case .abnt:
            let names: String
            func abnt(_ person: Person) -> String {
                person.given.isEmpty ? person.family.uppercased() : person.family.uppercased() + ", " + person.given
            }
            if people.isEmpty { names = "" }
            else if people.count > 3 || list.etAl { names = abnt(people[0]) + " et al." }
            else { names = people.map(abnt).joined(separator: "; ") }
            var text = names.isEmpty ? "" : sentence(names) + " "
            text += sentence(title)
            text += venue.isEmpty ? " \(year)." : " \(venue), \(year)."
            if !address.isEmpty { text += " Disponível em: " + address + "." }
            return text
        case .gbt7714:
            func name(_ person: Person) -> String {
                if isCJK(person.family) || isCJK(person.given) { return person.family + person.given }
                let initials = Authors.initials(person.given).replacingOccurrences(of: ".", with: "")
                return initials.isEmpty ? person.family.uppercased() : person.family.uppercased() + " " + initials
            }
            var names = people.prefix(3).map(name).joined(separator: ", ")
            if !people.isEmpty, people.count > 3 || list.etAl {
                names += isCJK(people[0].family) ? ", 等" : ", et al."
            }
            let code = gbCode(reference.kind)
            let doi = normalizedDOI(reference.doi)
            let web = reference.url.hasPrefix("file:") ? "" : reference.url
            var text = names.isEmpty ? "" : names + ". "
            text += title + "[\(code)]."
            if code == "EB/OL" {
                if let year = reference.year { text += " (\(year))." }
                if !venue.isEmpty { text += " " + sentence(venue) }
                if !web.isEmpty { text += " " + web + "." }
            } else {
                let source = [venue, reference.year.map(String.init) ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
                if !source.isEmpty { text += " " + source + "." }
                if doi.isEmpty, !web.isEmpty { text += " " + web + "." }
            }
            if !doi.isEmpty { text += " DOI:" + doi + "." }
            return text
        case .ieee:
            func ieee(_ person: Person) -> String {
                let initials = Authors.initials(person.given)
                return initials.isEmpty ? person.family : initials + " " + person.family
            }
            var names = ""
            if people.count > 6 || (list.etAl && !people.isEmpty) { names = ieee(people[0]) + " et al." }
            else if people.count == 2 { names = people.map(ieee).joined(separator: " and ") }
            else if people.count > 2 { names = people.dropLast().map(ieee).joined(separator: ", ") + ", and " + ieee(people[people.count - 1]) }
            else if let one = people.first { names = ieee(one) }
            var parts: [String] = []
            if !names.isEmpty { parts.append(names) }
            if !title.isEmpty { parts.append("\"\(title),\"") }
            var text = parts.joined(separator: ", ")
            if !venue.isEmpty { text += (text.isEmpty ? "" : " ") + venue + "," }
            text += (text.isEmpty ? "" : " ") + year + "."
            if !address.isEmpty { text += " [Online]. Available: " + address }
            return text
        }
    }
}
