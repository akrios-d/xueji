import Compression
import CoreGraphics
import Foundation
import PDFKit

/// Takes flattened highlights out of a PDF. They live in a form that the page draws last ("FFT0"), and PDFKit
/// paints them opaque over the text. The form is replaced by an empty one with an incremental update appended
/// to the file, so nothing else in the file is touched.
enum FlattenedFormsRemover {
    /// Empties the forms whose parts are all among `origins` (the highlights Xueji took over).
    /// Returns false, and leaves the file as it was, when anything looks unusual.
    static func neutralize(at url: URL, origins: [CGPoint]) -> Bool {
        guard let original = try? Data(contentsOf: url),
              let text = String(data: original, encoding: .isoLatin1),
              let expected = PDFDocument(url: url)?.pageCount else { return false }
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)

        var numbers: [Int] = []
        if let references = try? NSRegularExpression(pattern: #"/FFT0\s+(\d+)\s+0\s+R"#) {
            for match in references.matches(in: text, range: whole) {
                if let number = Int(ns.substring(with: match.range(at: 1))), !numbers.contains(number) {
                    numbers.append(number)
                }
            }
        }
        // Each flattened highlight is one line of the form ("q 1 0 0 1 x y cm /F7 Do Q"). Only the lines of the
        // highlights Xueji took over are dropped; anything else flattened into the page stays.
        var targets: [(number: Int, box: String, resources: String, content: String)] = []
        for number in numbers {
            guard let form = readForm(number, in: original, text: ns) else { continue }
            var kept: [String] = []
            var dropped = 0
            for line in form.content.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let moves = translations(in: line)
                let isOurs = !moves.isEmpty && moves.allSatisfy { move in
                    origins.contains { abs($0.x - move.x) < 0.5 && abs($0.y - move.y) < 0.5 }
                }
                if isOurs { dropped += 1 } else { kept.append(line) }
            }
            guard dropped > 0 else { continue }
            // A form that keeps something needs its resources to be copied; without them, only a form that is
            // left empty can be replaced.
            if !kept.isEmpty && form.resources == nil { continue }
            targets.append((number, form.box, form.resources ?? "<<>>", kept.joined(separator: "\n")))
        }
        guard !targets.isEmpty,
              let previous = lastStartXref(in: ns), previous < ns.length,
              ns.substring(from: previous).hasPrefix("xref"),
              let trailer = lastTrailer(in: ns) else { return false }

        var output = original
        output.append(Data("\n".utf8))
        var offsets: [(Int, Int)] = []
        for target in targets.sorted(by: { $0.number < $1.number }) {
            offsets.append((target.number, output.count))
            let object = "\(target.number) 0 obj\n<< /Type /XObject /Subtype /Form /FormType 1 \(target.box) /Resources \(target.resources) /Length \(target.content.utf8.count) >>\nstream\n\(target.content)\nendstream\nendobj\n"
            output.append(Data(object.utf8))
        }
        let tableStart = output.count
        var table = "xref\n"
        for (number, offset) in offsets { table += "\(number) 1\n" + String(format: "%010d 00000 n \n", offset) }
        table += "trailer\n<<\(trailer) /Prev \(previous)>>\nstartxref\n\(tableStart)\n%%EOF\n"
        output.append(Data(table.utf8))

        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try output.write(to: temporary)
            // The new file must open, have the same pages, and no flattened highlight left.
            guard let patched = PDFDocument(url: temporary), patched.pageCount == expected else { return false }
            var left = 0
            for index in 0..<patched.pageCount {
                if let page = patched.page(at: index) { left += FlatHighlightScanner.scan(page).count }
            }
            guard left < origins.count else { return false }
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            return true
        } catch {
            return false
        }
    }

    private static func translations(in content: String) -> [CGPoint] {
        guard let expression = try? NSRegularExpression(pattern: #"1\s+0\s+0\s+1\s+(-?[\d.]+)\s+(-?[\d.]+)\s+cm"#) else { return [] }
        let ns = content as NSString
        return expression.matches(in: content, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let x = Double(ns.substring(with: match.range(at: 1))),
                  let y = Double(ns.substring(with: match.range(at: 2))) else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    /// The text of the stream of object `number` and its /BBox, when the object is a plain stream with a direct length.
    private static func readForm(_ number: Int, in data: Data, text: NSString) -> (content: String, box: String, resources: String?)? {
        guard let header = try? NSRegularExpression(pattern: "(?<![0-9])\(number)\\s+0\\s+obj"),
              let found = header.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length)) else { return nil }
        let afterHeader = found.range.location + found.range.length
        let keyword = text.range(of: "stream", range: NSRange(location: afterHeader, length: text.length - afterHeader))
        guard keyword.location != NSNotFound else { return nil }
        let dictionary = text.substring(with: NSRange(location: afterHeader, length: keyword.location - afterHeader))
        let dictionaryText = dictionary as NSString
        let dictionaryRange = NSRange(location: 0, length: dictionaryText.length)
        guard !dictionary.contains("endobj"),
              let lengthExpression = try? NSRegularExpression(pattern: #"/Length\s+(\d+)(?!\s+\d+\s+R)"#),
              let lengthMatch = lengthExpression.firstMatch(in: dictionary, range: dictionaryRange),
              let length = Int(dictionaryText.substring(with: lengthMatch.range(at: 1))) else { return nil }
        var start = keyword.location + keyword.length
        if start < data.count, data[start] == 0x0D { start += 1 }
        if start < data.count, data[start] == 0x0A { start += 1 }
        guard start + length <= data.count else { return nil }
        let raw = data.subdata(in: start..<start + length)
        let decoded: Data? = dictionary.contains("FlateDecode") ? inflate(raw) : raw
        guard let decoded else { return nil }
        var box = "/BBox [0 0 612 792]"
        if let boxExpression = try? NSRegularExpression(pattern: #"/BBox\s*\[[^\]]*\]"#),
           let boxMatch = boxExpression.firstMatch(in: dictionary, range: dictionaryRange) {
            box = dictionaryText.substring(with: boxMatch.range)
        }
        return (String(decoding: decoded, as: UTF8.self), box, resourcesText(in: dictionary))
    }

    /// The /Resources entry of a form dictionary, exactly as written (a dictionary or a reference).
    private static func resourcesText(in dictionary: String) -> String? {
        guard let key = dictionary.range(of: "/Resources") else { return nil }
        let tail = dictionary[key.upperBound...].drop(while: { $0.isWhitespace })
        if let reference = tail.range(of: #"^\d+\s+0\s+R"#, options: .regularExpression) {
            return String(tail[reference])
        }
        guard tail.hasPrefix("<<") else { return nil }
        var depth = 0
        var index = tail.startIndex
        while index < tail.endIndex {
            let rest = tail[index...]
            if rest.hasPrefix("<<") {
                depth += 1
                index = tail.index(index, offsetBy: 2)
            } else if rest.hasPrefix(">>") {
                depth -= 1
                index = tail.index(index, offsetBy: 2)
                if depth == 0 { return String(tail[tail.startIndex..<index]) }
            } else {
                index = tail.index(after: index)
            }
        }
        return nil
    }

    private static func lastStartXref(in text: NSString) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: #"startxref\s+(\d+)"#),
              let match = expression.matches(in: text as String, range: NSRange(location: 0, length: text.length)).last else { return nil }
        return Int(text.substring(with: match.range(at: 1)))
    }

    /// The inside of the last trailer dictionary, without a /Prev entry.
    private static func lastTrailer(in text: NSString) -> String? {
        let keyword = text.range(of: "trailer", options: .backwards)
        guard keyword.location != NSNotFound else { return nil }
        let rest = text.substring(from: keyword.location + keyword.length)
        let restText = rest as NSString
        guard let expression = try? NSRegularExpression(pattern: #"<<(.*?)>>\s*startxref"#, options: [.dotMatchesLineSeparators]),
              let match = expression.firstMatch(in: rest, range: NSRange(location: 0, length: restText.length)) else { return nil }
        let inside = restText.substring(with: match.range(at: 1))
        return inside.replacingOccurrences(of: #"/Prev\s+\d+"#, with: "", options: .regularExpression)
    }

    private static func inflate(_ data: Data) -> Data? {
        guard data.count > 2 else { return nil }
        // The first two bytes are the zlib header; the rest is raw deflate.
        let payload = Data(data.dropFirst(2))
        var capacity = max(payload.count * 8, 1024)
        for _ in 0..<5 {
            var output = [UInt8](repeating: 0, count: capacity)
            let size = payload.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
                guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(&output, capacity, base, payload.count, nil, COMPRESSION_ZLIB)
            }
            if size > 0 && size < capacity { return Data(output[0..<size]) }
            capacity *= 4
        }
        return nil
    }
}
