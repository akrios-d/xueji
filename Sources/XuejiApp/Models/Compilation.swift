import Foundation
import XuejiCore

/// One draft in the compiled document.
struct CompilationSection: Codable, Equatable, Identifiable {
    /// The draft's id.
    var id: UUID
    var included = false
    /// 1 = chapter, 2 = section, 3 = subsection.
    var level = 1
}

/// How the student's drafts are put together into one document (one per workspace for now).
struct Compilation: Codable, Equatable {
    var title = ""
    /// The order of the drafts. Drafts missing from the list are added at the end, not included.
    var sections: [CompilationSection] = []
    var style: CitationStyle = .harvard
    var includeBibliography = true
    /// List sources that are linked to the drafts but never cited in the text.
    var includeUncited = false
    var includeContents = false

    /// Starts with the Chinese national standard when the app runs in Chinese, Harvard otherwise.
    init() {
        style = Locale.current.language.languageCode?.identifier == "zh" ? .gbt7714 : .harvard
    }

    /// Missing values take their defaults, so files written by an older version still load.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        sections = try values.decodeIfPresent([CompilationSection].self, forKey: .sections) ?? []
        style = try values.decodeIfPresent(CitationStyle.self, forKey: .style) ?? .harvard
        includeBibliography = try values.decodeIfPresent(Bool.self, forKey: .includeBibliography) ?? true
        includeUncited = try values.decodeIfPresent(Bool.self, forKey: .includeUncited) ?? false
        includeContents = try values.decodeIfPresent(Bool.self, forKey: .includeContents) ?? false
    }
}
