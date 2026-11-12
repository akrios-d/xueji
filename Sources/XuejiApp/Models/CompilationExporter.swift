import AppKit
import UniformTypeIdentifiers
import XuejiCore

/// Saves the compiled document as a Word, rich text or plain text file.
enum CompilationExporter {
    /// Asks where to save, then writes the file. Returns false when it could not be written
    /// (cancelling is not a failure).
    @MainActor
    static func export(_ blocks: [DocumentBlock], name: String, as format: DraftFormat) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = (clean.isEmpty ? L("compile.defaultName") : clean) + "." + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return true }
        do {
            try data(for: blocks, as: format).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func data(for blocks: [DocumentBlock], as format: DraftFormat) throws -> Data {
        switch format {
        case .word:
            return DocxWriter.data(for: blocks)
        case .plainText:
            return Data(DocumentBlock.plainText(blocks).utf8)
        case .richText:
            let document = attributedString(for: blocks)
            return try document.data(
                from: NSRange(location: 0, length: document.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        }
    }

    private static func attributedString(for blocks: [DocumentBlock]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func add(_ text: String, size: CGFloat, bold: Bool, indent: CGFloat = 0, centered: Bool = false, after: CGFloat = 8) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = after
            style.alignment = centered ? .center : .natural
            if indent > 0 {
                style.headIndent = indent
                style.firstLineHeadIndent = 0
            }
            result.append(NSAttributedString(string: text + "\n", attributes: [
                .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
                .paragraphStyle: style,
            ]))
        }
        for block in blocks {
            switch block {
            case .title(let text): add(text, size: 22, bold: true, centered: true, after: 18)
            case .contents: break
            case .heading(let level, let text): add(text, size: level == 1 ? 18 : level == 2 ? 15 : 13, bold: true, after: 8)
            case .paragraph(let text): add(text, size: 12, bold: false, after: 10)
            case .reference(let text): add(text, size: 11, bold: false, indent: 24, after: 4)
            }
        }
        return result
    }
}
