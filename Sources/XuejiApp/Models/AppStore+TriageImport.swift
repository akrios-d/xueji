import Foundation
import XuejiCore

/// What bringing a quote triage report in added.
struct TriageImportSummary: Equatable {
    /// Documents of the counts table that have no source card here (kept with the numbers of the report).
    var documents = 0
    /// Documents that were matched to a source card already in the Library.
    var linked = 0
    var quotes = 0
    var events = 0
}

/// Decides whether two titles are the same document, even when one was cleaned up or cut short.
enum TriageMatcher {
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
    func applyQuoteTriage(_ imported: ImportedQuoteTriage) -> TriageImportSummary {
        var summary = TriageImportSummary()
        let sources = workspace.items.values
            .filter { $0.trackID == trackID && $0.kind == .source && $0.approval == .approved }
            .map { (id: $0.id, title: $0.title) }

        // Fill the one being shown when it is empty; join the one with the same term; otherwise start another.
        let wanted = imported.term.lowercased()
        if triages.isEmpty {
            // The first one is created by the change below.
        } else if triage.isBlank {
            // Use it.
        } else if let same = triages.first(where: { !wanted.isEmpty && $0.term.lowercased() == wanted }) {
            selectTriage(same.id)
        } else {
            addTriage()
        }

        updateTriage { triage in
            if triage.title.isEmpty { triage.title = imported.title }
            if triage.term.isEmpty { triage.term = imported.term }
            if triage.modifier.isEmpty { triage.modifier = imported.modifier }
            if triage.corpusNote.isEmpty { triage.corpusNote = imported.corpusNote }
            if triage.caution.isEmpty { triage.caution = imported.caution }
            if triage.findings.isEmpty { triage.findings = imported.findings.joined(separator: "\n") }

            // Counts table: a document is matched to a source card, or kept with the numbers of the report.
            var documentIDs: [UUID] = []
            for document in imported.documents {
                if let match = TriageMatcher.best(document.title, among: sources) {
                    var note = triage.sourceNotes[match] ?? TriageSourceNote()
                    if note.date.isEmpty { note.date = document.date }
                    if note.usage.isEmpty { note.usage = document.usage }
                    triage.sourceNotes[match] = note
                    documentIDs.append(match)
                    summary.linked += 1
                } else if let known = triage.documents.first(where: { TriageMatcher.similarity($0.title, document.title) >= 0.9 }) {
                    documentIDs.append(known.id)
                } else {
                    let added = TriageDocument(
                        title: document.title, date: document.date, usage: document.usage,
                        words: document.words, term: document.term, modifier: document.modifier
                    )
                    triage.documents.append(added)
                    documentIDs.append(added.id)
                    summary.documents += 1
                }
            }

            // Quotes
            let places = sources + triage.documents.map { (id: $0.id, title: $0.title) }
            for quote in imported.quotes where !triage.quotes.contains(where: { $0.text == quote.text }) {
                var lines = quote.originLines
                var sourceID: UUID?
                if let index = lines.firstIndex(where: { line in
                    places.contains { $0.title.count >= 8 && TriageMatcher.similarity(line, $0.title) >= 0.8 }
                }) {
                    sourceID = TriageMatcher.best(lines[index], among: places)
                    lines.remove(at: index)
                }
                var speaker = "", locator = ""
                if lines.count >= 2 {
                    locator = lines[lines.count - 1]
                    speaker = lines.dropLast().joined(separator: " ")
                } else if let only = lines.first {
                    if only.contains(where: \.isNumber) { locator = only } else { speaker = only }
                }
                let kind: TriageKind
                switch quote.kind {
                case .essential: kind = .essential
                case .supporting: kind = .supporting
                case .counter: kind = .counter
                }
                triage.quotes.append(TriageQuote(
                    text: quote.text, sourceID: sourceID, speaker: speaker, locator: locator, kind: kind, why: quote.why
                ))
                summary.quotes += 1
            }

            // Timeline: an event is linked to the document with the same date, when exactly one has it.
            for event in imported.events
            where !triage.events.contains(where: { $0.date == event.date && $0.event == event.event }) {
                var sourceID: UUID?
                if !event.isGap {
                    let wanted = TriageMatcher.normalizedDate(event.date)
                    let same = imported.documents.indices.filter { TriageMatcher.normalizedDate(imported.documents[$0].date) == wanted }
                    if same.count == 1 { sourceID = documentIDs[same[0]] }
                }
                triage.events.append(TriageEvent(
                    date: event.date, sourceID: sourceID, event: event.event, who: event.who, frame: event.frame,
                    isGap: event.isGap
                ))
                summary.events += 1
            }
        }
        return summary
    }
}
