import Foundation
import XuejiCore

/// One source in the counts table.
struct EvidenceSourceRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    /// The source has a PDF on this Mac to count in.
    let hasPDF: Bool
    let included: Bool
    /// What the table shows: the student's text, or the card's year.
    let date: String
    let usage: String
    /// nil until the PDF has been read.
    let count: SourceCount?
    /// A document of an imported report: its numbers are fixed and it has no PDF here.
    var isFixed = false
}

/// Puts the triage together as a report: counts, quotes, timeline and findings.
enum EvidenceReport {
    static func blocks(evidence: EvidenceSet, rows: [EvidenceSourceRow], titles: [UUID: String]) -> [ReportBlock] {
        let term = evidence.term.trimmingCharacters(in: .whitespacesAndNewlines)
        let modifier = evidence.modifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let counted = rows.filter { $0.included && $0.hasPDF }
        var blocks: [ReportBlock] = []

        let title = evidence.title.trimmingCharacters(in: .whitespacesAndNewlines)
        blocks.append(.title(title.isEmpty ? L("evidence.defaultTitle") : title))
        blocks.append(.subtitle(Lf("evidence.report.subtitle", counted.count, term.isEmpty ? "—" : term)))
        let note = evidence.corpusNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { blocks.append(.callout(note, .gap)) }

        // 1. Counts
        blocks.append(.heading(Lf("evidence.report.s1", term.isEmpty ? "—" : term)))
        var columns = [
            ReportColumn("#", weight: 1), ReportColumn(L("evidence.col.document"), weight: 9),
            ReportColumn(L("evidence.col.date"), weight: 3), ReportColumn(L("evidence.col.words"), weight: 2),
            ReportColumn("“\(term)”", weight: 2), ReportColumn(L("evidence.col.density"), weight: 2),
        ]
        if !modifier.isEmpty { columns.append(ReportColumn(Lf("evidence.col.of", "\(modifier) \(term)"), weight: 3)) }
        columns.append(ReportColumn(L("evidence.col.usage"), weight: 10))
        let countRows: [[ReportCell]] = counted.enumerated().map { index, row in
            let count = row.count ?? SourceCount()
            var cells: [ReportCell] = [
                ReportCell("\(index + 1)"), ReportCell(row.title, bold: true), ReportCell(row.date),
                ReportCell(number(count.words)), ReportCell("\(count.term)"),
                ReportCell(String(format: "%.2f", TermCounter.perThousand(count.term, words: count.words))),
            ]
            if !modifier.isEmpty { cells.append(ReportCell("\(count.modifier)")) }
            cells.append(ReportCell(row.usage))
            return cells
        }
        blocks.append(.table(columns: columns, rows: countRows))
        let caution = evidence.caution.trimmingCharacters(in: .whitespacesAndNewlines)
        if !caution.isEmpty { blocks.append(.paragraph(caution)) }

        // 2. Quotes
        blocks.append(.heading(L("evidence.report.s2")))
        blocks.append(.paragraph(L("evidence.report.legend")))
        let quoteRows: [[ReportCell]] = evidence.quotes.enumerated().map { index, quote in
            let origin = [
                quote.speaker, quote.sourceID.flatMap { titles[$0] } ?? "", quote.locator,
            ].filter { !$0.isEmpty }.joined(separator: "\n")
            return [
                ReportCell("\(index + 1)"), ReportCell("“\(quote.text)”"), ReportCell(origin),
                ReportCell(L("evidence.kind." + quote.kind.rawValue).uppercased(), shade: shade(quote.kind), bold: true),
                ReportCell(quote.why),
            ]
        }
        blocks.append(.table(columns: [
            ReportColumn("#", weight: 1), ReportColumn(L("evidence.col.quote"), weight: 12),
            ReportColumn(L("evidence.col.origin"), weight: 6), ReportColumn(L("evidence.col.class"), weight: 3),
            ReportColumn(L("evidence.col.why"), weight: 12),
        ], rows: quoteRows))

        // 3. Timeline
        blocks.append(.heading(L("evidence.report.s3")))
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        func eventRow(_ event: EvidenceEvent) -> [ReportCell] {
            let shade: ReportShade? = event.isGap ? .gap : nil
            var count = "—"
            if !event.isGap {
                if let id = event.sourceID, let found = byID[id]?.count { count = "\(found.term)" } else { count = "" }
            }
            return [
                ReportCell(event.dateLabel, shade: shade, bold: true), ReportCell(event.event, shade: shade),
                ReportCell(event.who, shade: shade), ReportCell(event.frame, shade: shade),
                ReportCell(count, shade: shade),
            ]
        }
        // The periods as an outline: each one is a bold row followed by its events.
        var timelineRows: [[ReportCell]] = []
        for node in evidence.outline() {
            if let era = node.era {
                let quotes = era.quoteIDs.compactMap { id in evidence.quotes.first { $0.id == id }?.text }
                    .map { "“\($0)”" }.joined(separator: " ")
                let indent = String(repeating: "— ", count: max(0, node.depth - 1))
                timelineRows.append([
                    ReportCell(era.dateLabel, bold: true), ReportCell(indent + era.name, bold: true),
                    ReportCell(""), ReportCell(quotes), ReportCell(""),
                ])
            }
            timelineRows += evidence.events(in: node.era?.id).map(eventRow)
        }
        blocks.append(.table(columns: [
            ReportColumn(L("evidence.col.date"), weight: 3), ReportColumn(L("evidence.col.event"), weight: 7),
            ReportColumn(L("evidence.col.who"), weight: 6), ReportColumn(L("evidence.col.frame"), weight: 12),
            ReportColumn("“\(term)”", weight: 2),
        ], rows: timelineRows))
        if evidence.events.contains(where: \.isGap) { blocks.append(.paragraph(L("evidence.report.gapNote"))) }

        // 4. Findings
        let findings = evidence.findings.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !findings.isEmpty {
            blocks.append(.heading(L("evidence.report.s4")))
            blocks.append(.paragraph(Lf("evidence.report.findingsIntro", findings.count)))
            for (index, finding) in findings.enumerated() { blocks.append(.paragraph("\(index + 1). \(finding)")) }
        }
        blocks.append(.paragraph(L("evidence.report.method")))
        return blocks
    }

    private static func shade(_ kind: EvidenceKind) -> ReportShade {
        switch kind {
        case .essential: return .essential
        case .supporting: return .supporting
        case .counter: return .counter
        }
    }

    private static func number(_ value: Int) -> String {
        value.formatted(.number.locale(Localization.locale))
    }
}
