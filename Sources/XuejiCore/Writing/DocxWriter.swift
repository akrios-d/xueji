import Foundation

/// Writes a Word document (.docx) with real heading styles, so Word can build a table of contents.
/// A .docx is a zip of a few XML files; the zip is written here without compression, so nothing else is needed.
public enum DocxWriter {
    public static func data(for blocks: [DocumentBlock]) -> Data {
        var zip = ZipArchive()
        zip.add("[Content_Types].xml", contentTypes)
        zip.add("_rels/.rels", rootRelationships)
        zip.add("word/_rels/document.xml.rels", documentRelationships)
        zip.add("word/styles.xml", styles)
        zip.add("word/document.xml", document(for: blocks))
        return zip.data()
    }

    // MARK: Document

    static func document(for blocks: [DocumentBlock]) -> String {
        var body = ""
        for block in blocks {
            switch block {
            case .title(let text):
                body += paragraph(text, style: "Title")
            case .heading(let level, let text):
                body += paragraph(text, style: "Heading\(min(max(level, 1), 3))")
            case .paragraph(let text):
                body += paragraph(text, style: nil)
            case .reference(let text):
                body += paragraph(text, style: "Bibliography")
            case .contents(let title, let hint):
                body += paragraph(title, style: "TOCHeading")
                body += """
                <w:p><w:r><w:fldChar w:fldCharType="begin" w:dirty="true"/></w:r><w:r><w:instrText xml:space="preserve"> TOC \\o "1-3" \\h \\z \\u </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t xml:space="preserve">\(escape(hint))</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>
                """
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>
        """
    }

    /// One paragraph; a line break inside the text stays a line break.
    static func paragraph(_ text: String, style: String?) -> String {
        let properties = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
        let runs = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { "<w:r><w:t xml:space=\"preserve\">\(escape($0))</w:t></w:r>" }
            .joined(separator: "<w:r><w:br/></w:r>")
        return "<w:p>\(properties)\(runs)</w:p>"
    }

    /// XML-safe text: the five special characters are written as entities and control characters are dropped.
    static func escape(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default:
                if scalar.value >= 0x20 || scalar == "\t" { result.unicodeScalars.append(scalar) }
            }
        }
        return result
    }

    // MARK: Fixed parts

    static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
    """

    static let rootRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    """

    static let documentRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
    """

    static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="SimSun" w:cs="Times New Roman"/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="360" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="0" w:after="360"/><w:jc w:val="center"/></w:pPr><w:rPr><w:b/><w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="360" w:after="160"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="280" w:after="120"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:i/><w:sz w:val="26"/><w:szCs w:val="26"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="TOCHeading"><w:name w:val="TOC Heading"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="160"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Bibliography"><w:name w:val="Bibliography"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/><w:ind w:left="720" w:hanging="720"/></w:pPr></w:style></w:styles>
    """
}

/// A zip file made of stored (uncompressed) entries.
struct ZipArchive {
    private struct Entry {
        let name: [UInt8]
        let bytes: Data
        let crc: UInt32
        var offset: UInt32 = 0
    }

    private var entries: [Entry] = []

    mutating func add(_ name: String, _ text: String) {
        let bytes = Data(text.utf8)
        entries.append(Entry(name: Array(name.utf8), bytes: bytes, crc: Self.crc32(bytes)))
    }

    func data() -> Data {
        var out = Data()
        var placed: [Entry] = []
        for var entry in entries {
            entry.offset = UInt32(out.count)
            out.appendLE(UInt32(0x04034b50))
            out.appendLE(UInt16(20))                // version needed
            out.appendLE(UInt16(0x0800))            // names are UTF-8
            out.appendLE(UInt16(0))                 // stored
            out.appendLE(UInt16(0))                 // time
            out.appendLE(UInt16(0x0021))            // date: 1980-01-01
            out.appendLE(entry.crc)
            out.appendLE(UInt32(entry.bytes.count))
            out.appendLE(UInt32(entry.bytes.count))
            out.appendLE(UInt16(entry.name.count))
            out.appendLE(UInt16(0))                 // no extra field
            out.append(contentsOf: entry.name)
            out.append(entry.bytes)
            placed.append(entry)
        }
        let directoryStart = UInt32(out.count)
        for entry in placed {
            out.appendLE(UInt32(0x02014b50))
            out.appendLE(UInt16(20))                // made by
            out.appendLE(UInt16(20))                // version needed
            out.appendLE(UInt16(0x0800))
            out.appendLE(UInt16(0))
            out.appendLE(UInt16(0))
            out.appendLE(UInt16(0x0021))
            out.appendLE(entry.crc)
            out.appendLE(UInt32(entry.bytes.count))
            out.appendLE(UInt32(entry.bytes.count))
            out.appendLE(UInt16(entry.name.count))
            out.appendLE(UInt16(0))                 // extra
            out.appendLE(UInt16(0))                 // comment
            out.appendLE(UInt16(0))                 // disk
            out.appendLE(UInt16(0))                 // internal attributes
            out.appendLE(UInt32(0))                 // external attributes
            out.appendLE(entry.offset)
            out.append(contentsOf: entry.name)
        }
        let directorySize = UInt32(out.count) - directoryStart
        out.appendLE(UInt32(0x06054b50))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(placed.count))
        out.appendLE(UInt16(placed.count))
        out.appendLE(directorySize)
        out.appendLE(directoryStart)
        out.appendLE(UInt16(0))
        return out
    }

    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 != 0 ? 0xEDB88320 ^ (value >> 1) : value >> 1 }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xFFFF_FFFF
        for byte in data { value = table[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8) }
        return value ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
