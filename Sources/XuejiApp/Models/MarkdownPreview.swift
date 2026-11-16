import AppKit
import Foundation
import SwiftUI
import XuejiCore

/// Shows light Markdown in the app: bold and italic are applied; a formula stays as its LaTeX in a monospaced font
/// (Word shows it as a real equation once the document is exported).
enum MarkdownPreview {
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        var first = true
        for part in MarkdownBlocks.parts(of: text) {
            if !first { result.append(AttributedString("\n")) }
            first = false
            switch part {
            case .lines(let lines):
                for (index, line) in lines.enumerated() {
                    if index > 0 { result.append(AttributedString("\n")) }
                    result.append(inline(line))
                }
            case .bullet(let line):
                result.append(AttributedString("•  "))
                result.append(inline(line))
            case .numbered(let number, let line):
                result.append(AttributedString("\(number).  "))
                result.append(inline(line))
            case .display(let source):
                var math = AttributedString(source)
                math.font = .system(.body, design: .monospaced)
                result.append(math)
            }
        }
        return result
    }

    private static func inline(_ line: String) -> AttributedString {
        var result = AttributedString()
        for piece in MarkdownInline.pieces(line) {
            switch piece {
            case .text(let text, let bold, let italic):
                var run = AttributedString(text)
                if bold || italic {
                    var font = Font.body
                    if bold { font = font.bold() }
                    if italic { font = font.italic() }
                    run.font = font
                }
                result.append(run)
            case .math(let source):
                var math = AttributedString(source)
                math.font = .system(.body, design: .monospaced)
                result.append(math)
            }
        }
        return result
    }
}
