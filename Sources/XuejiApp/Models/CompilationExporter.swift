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
        /// A body paragraph with its bold and italic; lists keep their marks and formulas keep their LaTeX.
        func addMarkdown(_ text: String) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = 10
            let manager = NSFontManager.shared
            let line = NSMutableAttributedString()
            for (index, part) in MarkdownBlocks.parts(of: text).enumerated() {
                if index > 0 { line.append(NSAttributedString(string: "\n")) }
                var source: [String]
                switch part {
                case .lines(let lines): source = lines
                case .bullet(let text): source = ["•  " + text]
                case .numbered(let number, let text): source = ["\(number).  " + text]
                case .display(let math): source = ["$" + math + "$"]
                }
                for (row, text) in source.enumerated() {
                    if row > 0 { line.append(NSAttributedString(string: "\n")) }
                    for piece in MarkdownInline.pieces(text) {
                        var font = NSFont.systemFont(ofSize: 12)
                        var content = ""
                        switch piece {
                        case .text(let value, let bold, let italic):
                            content = value
                            if bold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
                            if italic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
                        case .math(let value):
                            content = value
                            font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                        }
                        line.append(NSAttributedString(string: content, attributes: [.font: font]))
                    }
                }
            }
            line.append(NSAttributedString(string: "\n"))
            line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
            result.append(line)
        }
        for block in blocks {
            switch block {
            case .title(let text): add(text, size: 22, bold: true, centered: true, after: 18)
            case .contents: break
            case .heading(let level, let text): add(text, size: level == 1 ? 18 : level == 2 ? 15 : 13, bold: true, after: 8)
            case .paragraph(let text): addMarkdown(text)
            case .reference(let text): add(text, size: 11, bold: false, indent: 24, after: 4)
            }
        }
        return result
    }
}
