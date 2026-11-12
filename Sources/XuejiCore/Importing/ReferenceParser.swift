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
            return ImportedReference(number: number, title: String(body.prefix(140)), doi: doi, url: url)
        }
        let split = splitTitle(groups[2])
        return ImportedReference(
            number: number,
            authors: groups[0],
            year: Int(groups[1].prefix(4)),
            title: split.title.isEmpty ? String(body.prefix(140)) : split.title,
            venue: split.venue,
            doi: doi,
            url: url
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

    private static func webURL(_ text: String) -> URL? {
        let clean = text.trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        guard let url = URL(string: clean), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
}
