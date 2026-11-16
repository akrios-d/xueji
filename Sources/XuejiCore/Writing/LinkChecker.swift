import Foundation

/// How a link answered.
public enum LinkStatus: Equatable, Sendable {
    case pending, checking
    /// Reached it; the number is the HTTP status.
    case ok(Int)
    /// The site answered but refuses automatic visits or asks for a login (401, 403, 429…): check it by hand.
    case blocked(Int)
    /// The page is gone or the server failed (404, 410, 5xx…).
    case broken(Int)
    /// No answer at all: no connection, unknown host, timeout.
    case unreachable

    public var isDone: Bool {
        if case .ok = self { return true }
        return false
    }
}

/// A reference of a pasted list that is online.
public struct ReferenceLink: Equatable, Sendable, Identifiable {
    public var id: Int { number }
    public let number: Int
    public let text: String
    public let url: URL
}

public enum LinkExtractor {
    /// The references that have a web link or a DOI, and how many have neither (those are not online and are skipped).
    public static func links(in input: String) -> (online: [ReferenceLink], offline: Int) {
        var online: [ReferenceLink] = []
        var offline = 0
        for entry in ReferenceParser.splitEntries(input) {
            if let url = link(in: entry.text) {
                online.append(ReferenceLink(number: entry.number, text: entry.text, url: url))
            } else {
                offline += 1
            }
        }
        return (online, offline)
    }

    static func link(in text: String) -> URL? {
        let parsed = ReferenceParser.parse(number: 0, text: text)
        if let url = parsed.url, isWeb(url) { return url }
        let trailing = CharacterSet(charactersIn: ".,;:)）。]”\"'’>")
        if let g = ImportText.captures(#"(https?://\S+)"#, in: text) {
            let raw = g[0].trimmingCharacters(in: trailing)
            if let url = makeURL(raw) { return url }
        }
        if let g = ImportText.captures(#"(?i)(?:doi:?\s*|doi\.org/)(10\.\d{4,9}/[^\s,;]+)"#, in: text) {
            return makeURL("https://doi.org/" + g[0].trimmingCharacters(in: trailing))
        }
        return nil
    }

    private static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host?.isEmpty == false
    }

    /// Links with Chinese characters or spaces still have to become URLs.
    private static func makeURL(_ text: String) -> URL? {
        if let url = URL(string: text), isWeb(url) { return url }
        let allowed = CharacterSet.urlHostAllowed.union(.urlPathAllowed).union(.urlQueryAllowed)
            .union(.urlFragmentAllowed).union(CharacterSet(charactersIn: "%#:/?&="))
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: encoded), isWeb(url) else { return nil }
        return url
    }
}

/// Visits a link and says whether it opens.
public struct LinkChecker: Sendable {
    /// The HTTP status of a request (method "HEAD" or "GET"); replaced in tests.
    public var statusCode: @Sendable (URL, String) async throws -> Int

    public init(statusCode: @escaping @Sendable (URL, String) async throws -> Int = LinkChecker.request) {
        self.statusCode = statusCode
    }

    public static let request: @Sendable (URL, String) async throws -> Int = { url, method in
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Xueji-LinkChecker",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/pdf,*/*;q=0.8", forHTTPHeaderField: "Accept")
        // Only the answer's header is wanted, not the file.
        let (_, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return http.statusCode
    }

    public func check(_ url: URL) async -> LinkStatus {
        do {
            var code = try await statusCode(url, "HEAD")
            // Many servers refuse HEAD but open the page; the page is what counts.
            if !(200..<300).contains(code) { code = try await statusCode(url, "GET") }
            return Self.classify(code)
        } catch {
            if let code = try? await statusCode(url, "GET") { return Self.classify(code) }
            return .unreachable
        }
    }

    static func classify(_ code: Int) -> LinkStatus {
        switch code {
        case 200..<300: return .ok(code)
        case 401, 403, 429, 999: return .blocked(code)
        default: return .broken(code)
        }
    }
}
