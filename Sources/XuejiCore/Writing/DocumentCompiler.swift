import Foundation

/// One piece of the assembled document.
public enum DocumentBlock: Equatable, Sendable {
    case title(String)
    /// A table of contents (filled in by Word); `hint` is shown until it is updated.
    case contents(title: String, hint: String)
    case heading(level: Int, text: String)
    case paragraph(String)
    /// A line of the bibliography, already formatted.
    case reference(String)

    /// The document as plain text: blocks separated by a blank line, references one per line.
    public static func plainText(_ blocks: [DocumentBlock]) -> String {
        var parts: [String] = []
        var lastWasReference = false
        for block in blocks {
            switch block {
            case .title(let text), .heading(_, let text), .paragraph(let text):
                parts.append(text)
                lastWasReference = false
            case .contents:
                break
            case .reference(let text):
                if lastWasReference, !parts.isEmpty {
                    parts[parts.count - 1] += "\n" + text
                } else {
                    parts.append(text)
                }
                lastWasReference = true
            }
        }
        return parts.joined(separator: "\n\n")
    }
}

/// A draft, ready to be placed in the document.
public struct CompileSection: Sendable {
    public var heading: String
    /// 1 (chapter) to 3.
    public var level: Int
    public var text: String
    /// The sources the draft is based on.
    public var linked: [UUID]

    public init(heading: String, level: Int, text: String, linked: [UUID]) {
        self.heading = heading
        self.level = level
        self.text = text
        self.linked = linked
    }
}

public struct CompiledDocument: Equatable, Sendable {
    public var blocks: [DocumentBlock]
    public var bibliography: [BibliographyEntry]
    public var unknownKeys: [String]
    public var incomplete: [IncompleteReference]
    /// Words in the body (not the bibliography).
    public var wordCount: Int
}

public enum DocumentCompiler {
    public static func compile(
        title: String,
        sections: [CompileSection],
        references: [Reference],
        style: CitationStyle,
        includeUncited: Bool,
        includeBibliography: Bool,
        contents: (title: String, hint: String)?,
        referencesHeading: String
    ) -> CompiledDocument {
        let output = Citations.process(
            texts: sections.map(\.text),
            linked: sections.flatMap(\.linked),
            references: references,
            style: style,
            includeUncited: includeUncited
        )
        var blocks: [DocumentBlock] = []
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty { blocks.append(.title(cleanTitle)) }
        if let contents { blocks.append(.contents(title: contents.title, hint: contents.hint)) }
        var words = 0
        for (index, section) in sections.enumerated() {
            let heading = section.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            if !heading.isEmpty { blocks.append(.heading(level: min(max(section.level, 1), 3), text: heading)) }
            for paragraph in paragraphs(of: output.texts[index]) {
                blocks.append(.paragraph(paragraph))
                words += paragraph.split(whereSeparator: { $0.isWhitespace }).count
            }
        }
        if includeBibliography, !output.bibliography.isEmpty {
            blocks.append(.heading(level: 1, text: referencesHeading))
            for entry in output.bibliography { blocks.append(.reference(entry.text)) }
        }
        return CompiledDocument(
            blocks: blocks, bibliography: output.bibliography, unknownKeys: output.unknownKeys,
            incomplete: output.incomplete, wordCount: words
        )
    }

    /// Paragraphs are separated by blank lines; a single line break stays inside its paragraph.
    public static func paragraphs(of text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
