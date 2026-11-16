import Foundation

extension DocxWriter {
    /// A landscape Word document with real tables, for the triage report.
    public static func reportData(for blocks: [ReportBlock]) -> Data {
        var zip = ZipArchive()
        zip.add("[Content_Types].xml", contentTypes)
        zip.add("_rels/.rels", rootRelationships)
        zip.add("word/_rels/document.xml.rels", documentRelationships)
        zip.add("word/styles.xml", reportStyles)
        zip.add("word/document.xml", reportDocument(for: blocks))
        return zip.data()
    }

    /// Landscape A4 with 0.5 inch margins: this many twentieths of a point are left for a table.
    static let reportWidth = 16838 - 2 * 720

    static func reportDocument(for blocks: [ReportBlock]) -> String {
        var body = ""
        for block in blocks {
            switch block {
            case .title(let text): body += paragraph(text, style: "Title")
            case .subtitle(let text): body += paragraph(text, style: "Subtitle")
            case .heading(let text): body += paragraph(text, style: "Heading1")
            case .paragraph(let text): body += paragraph(text, style: nil)
            case .callout(let text, let shade): body += callout(text, shade)
            case .table(let columns, let rows): body += table(columns, rows) + "<w:p/>"
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)<w:sectPr><w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/><w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" w:header="360" w:footer="360" w:gutter="0"/></w:sectPr></w:body></w:document>
        """
    }

    private static func callout(_ text: String, _ shade: ReportShade) -> String {
        let runs = text.components(separatedBy: "\n")
            .map { "<w:r><w:t xml:space=\"preserve\">\(escape($0))</w:t></w:r>" }
            .joined(separator: "<w:r><w:br/></w:r>")
        return "<w:p><w:pPr><w:pStyle w:val=\"Callout\"/><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(shade.fill)\"/></w:pPr>\(runs)</w:p>"
    }

    private static func cell(_ cell: ReportCell, width: Int, forcedShade: ReportShade? = nil, bold: Bool = false) -> String {
        var properties = "<w:tcW w:w=\"\(width)\" w:type=\"dxa\"/>"
        if let shade = forcedShade ?? cell.shade { properties += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(shade.fill)\"/>" }
        let run = bold || cell.bold ? "<w:rPr><w:b/></w:rPr>" : ""
        let paragraphs = cell.text.components(separatedBy: "\n").map {
            "<w:p><w:pPr><w:pStyle w:val=\"TableText\"/></w:pPr><w:r>\(run)<w:t xml:space=\"preserve\">\(escape($0))</w:t></w:r></w:p>"
        }.joined()
        return "<w:tc><w:tcPr>\(properties)</w:tcPr>\(paragraphs)</w:tc>"
    }

    static func table(_ columns: [ReportColumn], _ rows: [[ReportCell]]) -> String {
        guard !columns.isEmpty else { return "" }
        let weights = max(columns.reduce(0) { $0 + $1.weight }, 1)
        let widths = columns.map { reportWidth * $0.weight / weights }
        let line = "w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"BFBFBF\""
        var xml = "<w:tbl><w:tblPr><w:tblW w:w=\"\(reportWidth)\" w:type=\"dxa\"/>"
        xml += "<w:tblBorders><w:top \(line)/><w:left \(line)/><w:bottom \(line)/><w:right \(line)/><w:insideH \(line)/><w:insideV \(line)/></w:tblBorders>"
        xml += "<w:tblLayout w:type=\"fixed\"/><w:tblCellMar><w:top w:w=\"60\" w:type=\"dxa\"/><w:left w:w=\"100\" w:type=\"dxa\"/><w:bottom w:w=\"60\" w:type=\"dxa\"/><w:right w:w=\"100\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr>"
        xml += "<w:tblGrid>" + widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined() + "</w:tblGrid>"
        xml += "<w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>"
        for (index, column) in columns.enumerated() {
            xml += cell(ReportCell(column.title), width: widths[index], forcedShade: .header, bold: true)
        }
        xml += "</w:tr>"
        for row in rows {
            xml += "<w:tr><w:trPr><w:cantSplit/></w:trPr>"
            for index in columns.indices {
                xml += cell(index < row.count ? row[index] : ReportCell(""), width: widths[index])
            }
            xml += "</w:tr>"
        }
        return xml + "</w:tbl>"
    }

    static let reportStyles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="PingFang SC" w:cs="Calibri"/><w:sz w:val="21"/><w:szCs w:val="21"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style><w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="0" w:after="80"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="160"/></w:pPr><w:rPr><w:color w:val="595959"/><w:sz w:val="19"/><w:szCs w:val="19"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="280" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="TableText"><w:name w:val="Table Text"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:rPr><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style><w:style w:type="paragraph" w:styleId="Callout"><w:name w:val="Callout"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:pBdr><w:left w:val="single" w:sz="18" w:space="6" w:color="BF9000"/></w:pBdr><w:spacing w:before="80" w:after="160"/><w:ind w:left="140"/></w:pPr><w:rPr><w:sz w:val="19"/><w:szCs w:val="19"/></w:rPr></w:style></w:styles>
    """
}
