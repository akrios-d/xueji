import AppKit
import Observation
import XuejiCore

@Observable
final class ConverterViewModel: IConverterView, IConverterController {
    private(set) var input = ""
    private(set) var targetStyle: CitationStyle = .official
    private(set) var results: [ConvertedReference] = []

    func setInput(_ text: String) {
        input = text
        convert()
    }

    func setTargetStyle(_ style: CitationStyle) {
        targetStyle = style
        convert()
    }

    func copy(_ reference: ConvertedReference) { write(reference.text) }

    func copyAll() { write(results.map(\.text).joined(separator: "\n")) }

    func clear() { setInput("") }

    private func convert() {
        results = ReferenceConverter.convert(input, to: targetStyle)
    }

    private func write(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
