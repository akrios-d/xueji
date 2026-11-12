import AppKit
import PDFKit
import UniformTypeIdentifiers
import XuejiCore

/// A developer aid. Saves what the PDF reader sees in a file (page sizes, the words with their positions,
/// and what the importer made of them), so a PDF that is not recognised can be checked without guessing.
enum PDFDiagnostics {
    @MainActor
    static func saveReport() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.pdf]
        open.message = L("diagnostic.choose")
        guard open.runModal() == .OK, let url = open.url else { return }

        let report = makeReport(for: url)
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }

        let save = NSSavePanel()
        save.allowedContentTypes = [.json]
        save.nameFieldStringValue = "xueji-pdf-report.json"
        guard save.runModal() == .OK, let target = save.url else { return }
        try? data.write(to: target)
    }

    private static func makeReport(for url: URL) -> [String: Any] {
        var report: [String: Any] = ["file": url.lastPathComponent]
        guard let document = PDFDocument(url: url) else {
            report["error"] = "PDFDocument could not open the file"
            return report
        }
        report["pageCount"] = document.pageCount

        let readPages = try? PDFPageReader.pages(of: url)
        var pages: [[String: Any]] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let media = page.bounds(for: .mediaBox)
            let crop = page.bounds(for: .cropBox)
            let text = page.string ?? ""
            let nsText = text as NSString
            var sample: [[Double]] = []
            for position in 0..<min(nsText.length, 40) {
                let rect = page.characterBounds(at: position)
                sample.append([Double(nsText.character(at: position)), Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)])
            }
            let imported = readPages?[safe: index]
            pages.append([
                "number": index + 1,
                "rotation": page.rotation,
                "mediaBox": [Double(media.minX), Double(media.minY), Double(media.width), Double(media.height)],
                "cropBox": [Double(crop.minX), Double(crop.minY), Double(crop.width), Double(crop.height)],
                "stringLength": nsText.length,
                "stringStart": String(text.prefix(300)),
                "firstCharacters_code_x_y_w_h": sample,
                "words": (imported?.words ?? []).map { word -> [Any] in
                    [rounded(word.x0), rounded(word.x1), rounded(word.top), rounded(word.bottom), word.text]
                },
            ])
        }
        report["pages"] = pages

        if let readPages {
            do {
                switch try PDFImporter.parse(readPages) {
                case .sourceTriage(let sources): report["importResult"] = "source triage, \(sources.count) rows"
                case .statements(let rows, let references): report["importResult"] = "statements, \(rows.count) rows, \(references.count) references"
                }
            } catch {
                report["importResult"] = "not recognised: \(error)"
            }
        }
        return report
    }

    private static func rounded(_ value: Double) -> Double { (value * 10).rounded() / 10 }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
