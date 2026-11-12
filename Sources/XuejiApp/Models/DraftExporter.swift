import AppKit
import UniformTypeIdentifiers

enum DraftFormat: String, CaseIterable, Identifiable {
    case word, richText, plainText
    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .word: return "docx"
        case .richText: return "rtf"
        case .plainText: return "txt"
        }
    }

    var contentType: UTType {
        switch self {
        case .word: return UTType(filenameExtension: "docx") ?? .data
        case .richText: return .rtf
        case .plainText: return .plainText
        }
    }
}

/// Saves a draft as a file the student can open in Word or any editor.
enum DraftExporter {
    /// Asks where to save, then writes the file. Returns false when it could not be written
    /// (cancelling is not a failure).
    @MainActor
    static func export(_ draft: Draft, basedOn basis: String, as format: DraftFormat) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        let name = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = (name.isEmpty ? L("writing.untitled") : name) + "." + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return true }
        do {
            try data(for: draft, basedOn: basis, as: format).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func data(for draft: Draft, basedOn basis: String, as format: DraftFormat) throws -> Data {
        switch format {
        case .plainText:
            let title = draft.title.isEmpty ? "" : draft.title + "\n\n"
            return Data((title + draft.text + (basis.isEmpty ? "" : "\n\n" + basis)).utf8)
        case .richText, .word:
            let document = attributedString(for: draft, basedOn: basis)
            let type: NSAttributedString.DocumentType = format == .word ? .officeOpenXML : .rtf
            return try document.data(
                from: NSRange(location: 0, length: document.length),
                documentAttributes: [.documentType: type]
            )
        }
    }

    /// The title as a bold heading, then the text in paragraphs.
    private static func attributedString(for draft: Draft, basedOn basis: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if !draft.title.isEmpty {
            result.append(NSAttributedString(
                string: draft.title + "\n\n",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 20)]
            ))
        }
        result.append(NSAttributedString(
            string: draft.text,
            attributes: [.font: NSFont.systemFont(ofSize: 12)]
        ))
        if !basis.isEmpty {
            result.append(NSAttributedString(
                string: "\n\n" + basis,
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray]
            ))
        }
        return result
    }
}
