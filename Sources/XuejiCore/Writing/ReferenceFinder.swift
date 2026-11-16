import Foundation

/// A work found in an online catalogue.
public struct FoundReference: Equatable, Sendable, Identifiable {
    public let id = UUID()
    /// "Crossref" or "Open Library".
    public var source: String
    /// "Family, Given; Family, Given".
    public var authors: String
    public var year: Int?
    public var title: String
    /// The journal, or the book a chapter is in.
    public var venue: String
    public var publisher: String
    public var volume: String
    public var issue: String
    public var pages: String
    public var doi: String
    public var url: String
    /// journalArticle, book, bookChapter or webPage.
    public var kind: String

    /// The same work as a `Reference`, which the citation styles can print.
    public var reference: Reference {
        Reference(
            id: id, authors: authors, year: year, title: title,
            venue: kind == "book" ? publisher : venue,
            doi: doi, url: url, kind: kind, volume: volume, issue: issue, pages: pages,
            publisher: kind == "bookChapter" ? publisher : ""
        )
    }
}

/// Looks a work up by title, author or a phrase, in Crossref (articles, chapters, many books) and Open Library (books).
/// The catalogues give the work, never the page a quotation is on.
public struct ReferenceFinder: Sendable {
    /// Fetches a URL; replaced in tests.
    public var fetch: @Sendable (URL) async throws -> Data

    public init(fetch: @escaping @Sendable (URL) async throws -> Data = ReferenceFinder.download) {
        self.fetch = fetch
    }

    public static let download: @Sendable (URL) async throws -> Data = { url in
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Xueji (reference finder)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw URLError(.badServerResponse) }
        return data
    }

    /// Both catalogues at once; one being down does not hide the other's answers.
    public func find(_ query: String, limit: Int = 6) async -> [FoundReference] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        async let crossref = crossrefResults(text, limit: limit)
        async let library = openLibraryResults(text, limit: limit)
        let first = await crossref, second = await library
        // Interleave, so the best of each catalogue is near the top.
        var merged: [FoundReference] = []
        for index in 0..<max(first.count, second.count) {
            if index < first.count { merged.append(first[index]) }
            if index < second.count { merged.append(second[index]) }
        }
        return merged
    }

    func crossrefResults(_ query: String, limit: Int) async -> [FoundReference] {
        guard var parts = URLComponents(string: "https://api.crossref.org/works") else { return [] }
        parts.queryItems = [
            URLQueryItem(name: "query.bibliographic", value: query),
            URLQueryItem(name: "rows", value: String(limit)),
        ]
        guard let url = parts.url, let data = try? await fetch(url) else { return [] }
        return Self.parseCrossref(data)
    }

    func openLibraryResults(_ query: String, limit: Int) async -> [FoundReference] {
        guard var parts = URLComponents(string: "https://openlibrary.org/search.json") else { return [] }
        parts.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "fields", value: "key,title,author_name,first_publish_year,publisher"),
        ]
        guard let url = parts.url, let data = try? await fetch(url) else { return [] }
        return Self.parseOpenLibrary(data)
    }

    // MARK: Reading the answers

    static func parseCrossref(_ data: Data) -> [FoundReference] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any], let items = message["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let title = (item["title"] as? [String])?.first, !title.isEmpty else { return nil }
            let people = (item["author"] as? [[String: Any]] ?? []).compactMap { author -> String? in
                let family = (author["family"] as? String) ?? (author["name"] as? String) ?? ""
                let given = (author["given"] as? String) ?? ""
                if family.isEmpty { return nil }
                return given.isEmpty ? family : "\(family), \(given)"
            }
            let year = ((item["issued"] as? [String: Any])?["date-parts"] as? [[Int?]])?.first?.first.flatMap { $0 }
            let type = (item["type"] as? String) ?? ""
            let kind: String
            switch type {
            case "journal-article": kind = "journalArticle"
            case "book-chapter": kind = "bookChapter"
            case "book", "monograph", "edited-book", "reference-book": kind = "book"
            default: kind = type.contains("article") ? "journalArticle" : "book"
            }
            let doi = (item["DOI"] as? String) ?? ""
            return FoundReference(
                source: "Crossref", authors: people.joined(separator: "; "), year: year, title: title,
                venue: (item["container-title"] as? [String])?.first ?? "",
                publisher: (item["publisher"] as? String) ?? "",
                volume: (item["volume"] as? String) ?? "", issue: (item["issue"] as? String) ?? "",
                pages: ((item["page"] as? String) ?? "").replacingOccurrences(of: "–", with: "-"),
                doi: doi, url: doi.isEmpty ? "" : "https://doi.org/" + doi, kind: kind
            )
        }
    }

    static func parseOpenLibrary(_ data: Data) -> [FoundReference] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = root["docs"] as? [[String: Any]] else { return [] }
        return docs.compactMap { doc in
            guard let title = doc["title"] as? String, !title.isEmpty else { return nil }
            let names = doc["author_name"] as? [String] ?? []
            let key = (doc["key"] as? String) ?? ""
            return FoundReference(
                source: "Open Library", authors: names.joined(separator: "; "),
                year: doc["first_publish_year"] as? Int, title: title, venue: "",
                publisher: (doc["publisher"] as? [String])?.first ?? "", volume: "", issue: "", pages: "",
                doi: "", url: key.isEmpty ? "" : "https://openlibrary.org" + key, kind: "book"
            )
        }
    }
}
