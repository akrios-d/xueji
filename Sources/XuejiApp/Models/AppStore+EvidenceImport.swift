import Foundation
import XuejiCore

/// What bringing a quote triage report in added.
struct EvidenceImportSummary: Equatable {
    /// Documents of the counts table that have no source card here (kept with the numbers of the report).
    var documents = 0
    /// Documents that were matched to a source card already in the Library.
    var linked = 0
    var quotes = 0
    var periods = 0
    var events = 0
}

/// Decides whether two titles are the same document, even when one was cleaned up or cut short.
enum EvidenceMatcher {
    static func tokens(_ text: String) -> Set<String> {
        var result: Set<String> = []
        var word = ""
        func flush() {
            if word.count >= 3 { result.insert(word) }
            word = ""
        }
        for scalar in text.lowercased().unicodeScalars {
            if (0x3400...0x4DBF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value) {
                flush()
                result.insert(String(scalar))
            } else if CharacterSet.alphanumerics.contains(scalar) {
                word.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return result
    }

    /// The share of the shorter title's words that the other one has too, from 0 to 1.
    static func similarity(_ a: String, _ b: String) -> Double {
        let left = tokens(a), right = tokens(b)
        let smaller = min(left.count, right.count)
        guard smaller >= 2 else { return 0 }
        return Double(left.intersection(right).count) / Double(smaller)
    }

    /// The candidate that looks most like `title`, when it looks enough like it.
    static func best(_ title: String, among candidates: [(id: UUID, title: String)]) -> UUID? {
        let scored = candidates.map { ($0.id, similarity(title, $0.title)) }.filter { $0.1 >= 0.7 }
        return scored.max { $0.1 < $1.1 }?.0
    }

    static func normalizedDate(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

extension AppStore {
    /// Fills the Triage of the current project from an imported report. Nothing is overwritten: texts the student
    /// already wrote stay, and quotes, documents and events that are already there are skipped.
    func applyEvidenceReport(_ imported: ImportedEvidenceReport) -> EvidenceImportSummary {
        var summary = EvidenceImportSummary()
        let sources = workspace.items.values
            .filter { $0.trackID == trackID && $0.kind == .source && $0.approval == .approved }
            .map { (id: $0.id, title: $0.title) }

        // Fill the one being shown when it is empty; join the one with the same term; otherwise start another.
        let wanted = imported.term.lowercased()
        if triages.isEmpty {
            // The first one is created by the change below.
        } else if evidence.isBlank {
            // Use it.
        } else if let same = triages.first(where: { !wanted.isEmpty && $0.term.lowercased() == wanted }) {
            selectEvidence(same.id)
        } else {
            addEvidence()
        }

        updateEvidence { evidence in
            if evidence.title.isEmpty { evidence.title = imported.title }
            if evidence.term.isEmpty { evidence.term = imported.term }
            if evidence.modifier.isEmpty { evidence.modifier = imported.modifier }
            if evidence.corpusNote.isEmpty { evidence.corpusNote = imported.corpusNote }
            if evidence.caution.isEmpty { evidence.caution = imported.caution }
            if evidence.findings.isEmpty { evidence.findings = imported.findings.joined(separator: "\n") }

            // Counts table: a document is matched to a source card, or kept with the numbers of the report.
            var documentIDs: [UUID] = []
            for document in imported.documents {
                if let match = EvidenceMatcher.best(document.title, among: sources) {
                    var note = evidence.sourceNotes[match] ?? EvidenceSourceNote()
                    if note.date.isEmpty { note.date = document.date }
                    if note.usage.isEmpty { note.usage = document.usage }
                    evidence.sourceNotes[match] = note
                    documentIDs.append(match)
                    summary.linked += 1
                } else if let known = evidence.documents.first(where: { EvidenceMatcher.similarity($0.title, document.title) >= 0.9 }) {
                    documentIDs.append(known.id)
                } else {
                    let added = EvidenceDocument(
                        title: document.title, date: document.date, usage: document.usage,
                        words: document.words, term: document.term, modifier: document.modifier
                    )
                    evidence.documents.append(added)
                    documentIDs.append(added.id)
                    summary.documents += 1
                }
            }

            // Quotes
            let places = sources + evidence.documents.map { (id: $0.id, title: $0.title) }
            var quoteIDByNumber: [Int: UUID] = [:]
            for quote in imported.quotes {
                if let known = evidence.quotes.first(where: { $0.text == quote.text }) {
                    quoteIDByNumber[quote.number] = known.id
                    continue
                }
                var lines = quote.originLines
                var sourceID: UUID?
                if let index = lines.firstIndex(where: { line in
                    places.contains { $0.title.count >= 8 && EvidenceMatcher.similarity(line, $0.title) >= 0.8 }
                }) {
                    sourceID = EvidenceMatcher.best(lines[index], among: places)
                    lines.remove(at: index)
                }
                var speaker = "", locator = ""
                if lines.count >= 2 {
                    locator = lines[lines.count - 1]
                    speaker = lines.dropLast().joined(separator: " ")
                } else if let only = lines.first {
                    if only.contains(where: \.isNumber) { locator = only } else { speaker = only }
                }
                let kind: EvidenceKind
                switch quote.kind {
                case .essential: kind = .essential
                case .supporting: kind = .supporting
                case .counter: kind = .counter
                }
                let added = EvidenceQuote(
                    text: quote.text, sourceID: sourceID, speaker: speaker, locator: locator, kind: kind, why: quote.why
                )
                evidence.quotes.append(added)
                quoteIDByNumber[quote.number] = added.id
                summary.quotes += 1
            }

            // Periods: each one sits inside the period it names, or directly in the whole timeline.
            func key(_ name: String) -> String { EvidenceMatcher.normalizedDate(name) }
            var eraIDByName: [String: UUID] = [:]
            var newEras: [(era: UUID, parent: String)] = []
            for period in imported.periods {
                if let known = evidence.eras.first(where: { key($0.name) == key(period.name) }) {
                    eraIDByName[key(period.name)] = known.id
                    continue
                }
                guard let from = EvidenceDate.parse(period.from) else { continue }
                let era = EvidenceEra(
                    name: period.name, from: from, until: EvidenceDate.parse(period.until) ?? from,
                    quoteIDs: period.quotes.compactMap { quoteIDByNumber[$0] }
                )
                evidence.eras.append(era)
                eraIDByName[key(period.name)] = era.id
                newEras.append((era.id, period.parent))
                summary.periods += 1
            }
            for (id, parent) in newEras where !parent.isEmpty {
                guard let parentID = eraIDByName[key(parent)], parentID != id,
                      let index = evidence.eras.firstIndex(where: { $0.id == id }) else { continue }
                evidence.eras[index].parentID = parentID
            }

            // Timeline: an event is linked to the document with the same date, when exactly one has it.
            for event in imported.events {
                // The date text becomes a real date (or period), so the event can be drawn on the chart.
                let period = EvidenceDate.parsePeriod(event.date)
                let label = period.map { EvidenceDate.label(from: $0.from, until: $0.until) } ?? event.date
                if evidence.events.contains(where: { $0.date == label && $0.event == event.event }) { continue }
                var sourceID: UUID?
                if !event.isGap {
                    let wanted = EvidenceMatcher.normalizedDate(event.date)
                    let same = imported.documents.indices.filter { EvidenceMatcher.normalizedDate(imported.documents[$0].date) == wanted }
                    if same.count == 1 { sourceID = documentIDs[same[0]] }
                }
                // A quote that shows the event gives it its document.
                let quoteID = event.isGap ? nil : event.quoteNumber.flatMap { quoteIDByNumber[$0] }
                if let quoteID, let linked = evidence.quotes.first(where: { $0.id == quoteID })?.sourceID { sourceID = linked }
                evidence.events.append(EvidenceEvent(
                    date: label, when: period?.from, until: period?.until, sourceID: sourceID, quoteID: quoteID,
                    eraID: eraIDByName[key(event.period)], event: event.event, who: event.who, frame: event.frame,
                    isGap: event.isGap
                ))
                summary.events += 1
            }
        }
        return summary
    }
}
