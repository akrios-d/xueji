import AppKit
import CoreGraphics
import PDFKit

/// A highlight that was painted into the page itself (a PDF saved or printed with its highlights "flattened").
struct FlatHighlight: Equatable {
    let rect: CGRect
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    var hex: String {
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

/// Brings the highlights that a PDF already has into Xueji's own format, with their colours,
/// so they show up in the reader's list, can get notes and can be quoted.
enum HighlightImporter {
    struct Result: Equatable {
        var count = 0
        /// "RRGGBB" of every colour found, in order of appearance, without repeats.
        var colors: [String] = []
        /// Flattened highlights were found but their painted copies could not be taken out of the file.
        var leftPainted = false
    }

    /// Converts the highlights and underlines of the file at `url` (a copy that belongs to Xueji).
    /// The file is rewritten only when something was found.
    static func convert(at url: URL) -> Result {
        // Flattened highlights are found first, on the file as it came.
        guard let scanned = PDFDocument(url: url) else { return Result() }
        var flat: [[FlatHighlight]] = []
        for index in 0..<scanned.pageCount {
            flat.append(scanned.page(at: index).map(FlatHighlightScanner.scan) ?? [])
        }
        // A flattened highlight is painted over the text and can hide it. Once Xueji has its own mark for it,
        // the painted copy is taken out of the file.
        let origins = flat.flatMap { $0 }.map { $0.rect.origin }
        let removed = origins.isEmpty || FlattenedFormsRemover.neutralize(at: url, origins: origins)

        guard let document = PDFDocument(url: url) else { return Result() }
        var result = Result()
        func note(_ hex: String) {
            result.count += 1
            if !result.colors.contains(hex) { result.colors.append(hex) }
        }

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations {
                guard annotation.userName?.hasPrefix(ReadingFiles.markPrefix) != true,
                      let kind = markKind(of: annotation), let hex = annotation.color.hexString else { continue }
                convertAnnotation(annotation, on: page, kind: kind, hex: hex)
                note(hex)
            }
            var seen: Set<String> = []
            let fills = (index < flat.count ? flat[index] : []).filter { seen.insert("\($0.rect)-\($0.hex)").inserted }
            // A painted highlight is one rectangle per line; the lines of one passage become one mark.
            for block in blocks(of: fills, on: page) {
                let group = UUID().uuidString
                for fill in block { addHighlight(on: page, rect: fill.rect, hex: fill.hex, group: group) }
                note(block[0].hex)
            }
        }
        result.leftPainted = !removed
        guard result.count > 0 else { return result }
        do { try ReadingFiles.write(document, to: url) } catch { return Result() }
        return result
    }

    // MARK: Real annotations

    private static func markKind(of annotation: PDFAnnotation) -> MarkKind? {
        switch annotation.type {
        case "Highlight": return .highlight
        case "Underline": return .underline
        default: return nil
        }
    }

    /// Replaces a highlight made by another app with one mark per line, named in Xueji's format.
    /// The note, if there is one, goes to the first line.
    private static func convertAnnotation(_ annotation: PDFAnnotation, on page: PDFPage, kind: MarkKind, hex: String) {
        let group = UUID().uuidString
        let name = "\(ReadingFiles.markPrefix)\(group):\(kind.rawValue):\(hex)"
        let points = (annotation.quadrilateralPoints ?? []).map(\.pointValue)
        guard points.count >= 4, points.count % 4 == 0 else {
            annotation.userName = name
            return
        }
        let origin = annotation.bounds.origin
        let color = annotation.color
        let note = annotation.contents
        page.removeAnnotation(annotation)
        for start in stride(from: 0, to: points.count, by: 4) {
            let quad = points[start..<start + 4].map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
            let xs = quad.map(\.x), ys = quad.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
                  maxX > minX, maxY > minY else { continue }
            let line = makeMark(
                rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), kind: kind, color: color
            )
            line.userName = name
            if start == 0 { line.contents = note }
            page.addAnnotation(line)
        }
    }

    // MARK: Flattened highlights

    /// Painted rectangles of one colour that are the lines of one passage, top to bottom. Line B continues line A
    /// (the one above it) only when A runs to the end of its text line and B starts at the beginning of its own:
    /// two highlights in the middle of two neighbouring lines are two highlights, not one.
    static func blocks(of fills: [FlatHighlight], on page: PDFPage) -> [[FlatHighlight]] {
        var parent = Array(0..<fills.count)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        for i in fills.indices {
            for j in fills.indices where j > i && fills[i].hex == fills[j].hex {
                let (upper, lower) = fills[i].rect.maxY >= fills[j].rect.maxY ? (fills[i].rect, fills[j].rect) : (fills[j].rect, fills[i].rect)
                let height = min(upper.height, lower.height)
                let gap = upper.minY - lower.maxY
                guard gap <= height * 0.6, gap >= -height else { continue }
                if endsTextLine(upper, on: page) && startsTextLine(lower, on: page) { parent[root(i)] = root(j) }
            }
        }
        var groups: [Int: [FlatHighlight]] = [:]
        for i in fills.indices { groups[root(i), default: []].append(fills[i]) }
        return groups.values
            .map { $0.sorted { $0.rect.maxY > $1.rect.maxY || ($0.rect.maxY == $1.rect.maxY && $0.rect.minX < $1.rect.minX) } }
            .sorted { $0[0].rect.maxY > $1[0].rect.maxY }
    }

    /// Whether there is no text on the same line right after the rectangle.
    private static func endsTextLine(_ rect: CGRect, on page: PDFPage) -> Bool {
        let probe = CGRect(x: rect.maxX + rect.height * 0.3, y: rect.midY - rect.height * 0.15, width: rect.height * 1.5, height: rect.height * 0.3)
        return !hasText(in: probe, on: page)
    }

    /// Whether there is no text on the same line right before the rectangle.
    private static func startsTextLine(_ rect: CGRect, on page: PDFPage) -> Bool {
        let width = rect.height * 1.5
        let probe = CGRect(x: rect.minX - rect.height * 0.3 - width, y: rect.midY - rect.height * 0.15, width: width, height: rect.height * 0.3)
        return !hasText(in: probe, on: page)
    }

    private static func hasText(in rect: CGRect, on page: PDFPage) -> Bool {
        let box = page.bounds(for: .mediaBox)
        let inside = rect.intersection(box)
        guard !inside.isNull, inside.width > 0 else { return false }
        let text = page.selection(for: inside)?.string ?? ""
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func addHighlight(on page: PDFPage, rect: CGRect, hex: String, group: String) {
        guard let base = NSColor(hex: hex) else { return }
        let mark = makeMark(rect: rect, kind: .highlight, color: base.withAlphaComponent(0.45))
        mark.userName = "\(ReadingFiles.markPrefix)\(group):\(MarkKind.highlight.rawValue):\(hex)"
        page.addAnnotation(mark)
    }

    private static func makeMark(rect: CGRect, kind: MarkKind, color: NSColor) -> PDFAnnotation {
        let annotation = PDFAnnotation(
            bounds: rect, forType: kind == .highlight ? .highlight : .underline, withProperties: nil
        )
        let w = rect.width, h = rect.height
        annotation.quadrilateralPoints = [
            CGPoint(x: 0, y: h), CGPoint(x: w, y: h), CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0),
        ].map { NSValue(point: $0) }
        annotation.color = color
        return annotation
    }

    /// A short name for a colour ("Red", "Green"…), from its hue.
    static func colorName(hex: String) -> String {
        guard let color = NSColor(hex: hex)?.usingColorSpace(.sRGB) else { return "#" + hex }
        if color.saturationComponent < 0.15 { return L("color.named.gray") }
        let hue = color.hueComponent
        switch hue {
        case ..<0.03, 0.95...: return L("color.named.red")
        case ..<0.11: return L("color.named.orange")
        case ..<0.2: return L("color.named.yellow")
        case ..<0.45: return L("color.named.green")
        case ..<0.55: return L("color.named.cyan")
        case ..<0.72: return L("color.named.blue")
        case ..<0.85: return L("color.named.purple")
        default: return L("color.named.pink")
        }
    }
}

/// Reads a page's drawing instructions and finds the coloured rectangles painted with the "multiply" blend,
/// which is how flattened highlights are stored (each one in its own nested form, inside the page's form).
final class FlatHighlightScanner {
    private struct State {
        var ctm = CGAffineTransform.identity
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var multiply = false
    }

    private var state = State()
    private var stack: [State] = []
    private var points: [CGPoint] = []
    private var fills: [FlatHighlight] = []
    private var current: CGPDFContentStreamRef?
    private var depth = 0

    static func scan(_ page: PDFPage) -> [FlatHighlight] {
        guard let pageRef = page.pageRef else { return [] }
        let scanner = FlatHighlightScanner()
        let stream: CGPDFContentStreamRef? = CGPDFContentStreamCreateWithPage(pageRef)
        guard let stream else { return [] }
        scanner.run(stream)
        CGPDFContentStreamRelease(stream)
        return scanner.fills
    }

    private func run(_ stream: CGPDFContentStreamRef) {
        let previous = current
        current = stream
        let scanner: CGPDFScannerRef? = CGPDFScannerCreate(stream, Self.table, Unmanaged.passUnretained(self).toOpaque())
        if let scanner {
            _ = CGPDFScannerScan(scanner)
            CGPDFScannerRelease(scanner)
        }
        current = previous
    }

    // MARK: Painting

    private func paint() {
        defer { points = [] }
        guard state.multiply, !points.isEmpty else { return }
        let r = state.red, g = state.green, b = state.blue
        // White, black and grey are never highlights.
        guard max(r, g, b) - min(r, g, b) > 0.12 else { return }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        // About the size of a line of text.
        guard rect.width >= 3, rect.height >= 4, rect.height <= 60 else { return }
        fills.append(FlatHighlight(rect: rect, red: r, green: g, blue: b))
    }

    private func add(x: CGFloat, y: CGFloat) {
        points.append(CGPoint(x: x, y: y).applying(state.ctm))
    }

    private func draw(form stream: CGPDFStreamRef, resources: CGPDFDictionaryRef?, matrix: CGAffineTransform) {
        guard depth < 8 else { return }
        guard let parent = current, let own = CGPDFStreamGetDictionary(stream) else { return }
        // A form without resources of its own uses the ones of the page that draws it.
        let nested: CGPDFContentStreamRef? = CGPDFContentStreamCreateWithStream(stream, resources ?? own, parent)
        guard let nested else { return }
        let saved = state, savedStack = stack, savedPoints = points
        state.ctm = matrix.concatenating(state.ctm)
        stack = []
        points = []
        depth += 1
        run(nested)
        depth -= 1
        state = saved
        stack = savedStack
        points = savedPoints
        CGPDFContentStreamRelease(nested)
    }

    // MARK: Operators

    private static func owner(_ info: UnsafeMutableRawPointer?) -> FlatHighlightScanner {
        Unmanaged<FlatHighlightScanner>.fromOpaque(info!).takeUnretainedValue()
    }

    private static func numbers(_ scanner: CGPDFScannerRef) -> [CGFloat] {
        var values: [CGFloat] = []
        var value: CGFloat = 0
        while CGPDFScannerPopNumber(scanner, &value) { values.insert(value, at: 0) }
        return values
    }

    private func setColor(_ values: [CGFloat]) {
        switch values.count {
        case 1:
            state.red = values[0]; state.green = values[0]; state.blue = values[0]
        case 3:
            state.red = values[0]; state.green = values[1]; state.blue = values[2]
        case 4:
            let k = values[3]
            state.red = (1 - values[0]) * (1 - k)
            state.green = (1 - values[1]) * (1 - k)
            state.blue = (1 - values[2]) * (1 - k)
        default:
            break
        }
    }

    private static let table: CGPDFOperatorTableRef = {
        let table = CGPDFOperatorTableCreate()!
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            let me = owner(info)
            me.stack.append(me.state)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let me = owner(info)
            if let last = me.stack.popLast() { me.state = last }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let me = owner(info)
            let v = numbers(scanner)
            guard v.count == 6 else { return }
            let matrix = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
            me.state.ctm = matrix.concatenating(me.state.ctm)
        }
        for name in ["rg", "g", "k", "sc", "scn"] {
            CGPDFOperatorTableSetCallback(table, name) { scanner, info in
                owner(info).setColor(numbers(scanner))
            }
        }
        CGPDFOperatorTableSetCallback(table, "gs") { scanner, info in
            let me = owner(info)
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name, let stream = me.current,
                  let object = CGPDFContentStreamGetResource(stream, "ExtGState", name) else { return }
            var dictionary: CGPDFDictionaryRef?
            guard CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary else { return }
            var blend: UnsafePointer<CChar>?
            if CGPDFDictionaryGetName(dictionary, "BM", &blend), let blend {
                me.state.multiply = String(cString: blend) == "Multiply"
            }
        }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            let me = owner(info)
            let v = numbers(scanner)
            guard v.count == 4 else { return }
            me.add(x: v[0], y: v[1])
            me.add(x: v[0] + v[2], y: v[1])
            me.add(x: v[0] + v[2], y: v[1] + v[3])
            me.add(x: v[0], y: v[1] + v[3])
        }
        for name in ["m", "l"] {
            CGPDFOperatorTableSetCallback(table, name) { scanner, info in
                let v = numbers(scanner)
                guard v.count == 2 else { return }
                owner(info).add(x: v[0], y: v[1])
            }
        }
        for name in ["f", "F", "f*", "B", "B*", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, name) { _, info in owner(info).paint() }
        }
        for name in ["n", "S", "s"] {
            CGPDFOperatorTableSetCallback(table, name) { _, info in owner(info).points = [] }
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let me = owner(info)
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name, let current = me.current,
                  let object = CGPDFContentStreamGetResource(current, "XObject", name) else { return }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream) else { return }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype,
                  String(cString: subtype) == "Form" else { return }
            var matrix = CGAffineTransform.identity
            var array: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(dictionary, "Matrix", &array), let array, CGPDFArrayGetCount(array) == 6 {
                var v = [CGFloat](repeating: 0, count: 6)
                for index in 0..<6 { _ = CGPDFArrayGetNumber(array, index, &v[index]) }
                matrix = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
            }
            var resources: CGPDFDictionaryRef?
            _ = CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
            me.draw(form: stream, resources: resources, matrix: matrix)
        }
        return table
    }()
}
