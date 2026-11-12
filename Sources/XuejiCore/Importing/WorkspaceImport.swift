import Foundation

extension Workspace {
    /// Turns a parsed PDF into cards that wait in the Inbox. Nothing an import creates counts as approved:
    /// the student looks at every card, as with an agent's proposals. Rows already in the track are skipped,
    /// so importing the same PDF twice adds nothing.
    @discardableResult
    public mutating func importDocument(
        _ document: ImportedDocument, trackID: UUID, by actorID: UUID, fileName: String, at now: Date = Date()
    ) throws -> ImportSummary {
        guard try activeMember(actorID).kind == .human else { throw XuejiError.notPermitted }
        guard tracks[trackID] != nil else { throw XuejiError.trackNotFound }

        var summary = ImportSummary()
        // Cards created in one import keep the order of the document in the Inbox.
        var tick = 0
        func nextDate() -> Date {
            tick += 1
            return now.addingTimeInterval(Double(tick) * 0.001)
        }

        switch document {
        case .sourceTriage(let sources):
            for source in sources {
                guard let url = source.url else {
                    summary.skippedWithoutLink += 1
                    continue
                }
                if matchingSourceID(trackID: trackID, title: source.title, url: url, urlIsExact: false) != nil {
                    summary.skippedDuplicates += 1
                    continue
                }
                var values: [String: FieldValue] = [:]
                if !source.venue.isEmpty { values["venue"] = .text(source.venue) }
                if let year = source.year { values["year"] = .number(Double(year)) }
                if !source.phase.isEmpty { values["phase"] = .text(source.phase) }
                if let position = source.readingOrder { values["readingOrder"] = .number(Double(position)) }
                if !source.triageNote.isEmpty { values["triageNote"] = .text(source.triageNote) }
                if !source.linkAsShown.isEmpty {
                    values["caveats"] = .text(
                        "The PDF showed a shortened link (\(source.linkAsShown)). Only the site is exact: open it and find the full address."
                    )
                }
                _ = try propose(
                    trackID: trackID, typeID: ItemType.sourceID, title: source.title,
                    details: source.readingReason.isEmpty ? "" : "Why read it now: " + source.readingReason,
                    url: url, classification: source.classification, values: values, actorID: actorID,
                    fileName: fileName, at: nextDate()
                )
                summary.sourcesAdded += 1
            }

        case .statements(let statements, let references):
            var sourceIDs: [Int: UUID] = [:]
            for statement in statements {
                let title = statement.dateLabel.isEmpty ? statement.actor : statement.actor + " · " + statement.dateLabel
                if statementExists(trackID: trackID, title: title, position: statement.position) {
                    summary.skippedDuplicates += 1
                    continue
                }

                var values: [String: FieldValue] = [
                    "actor": .text(statement.actor),
                    "position": .text(statement.position),
                    "verification": .select("toVerify"),
                ]
                if let kind = statement.actorKind { values["actorKind"] = .select(kind) }
                if let day = statement.date {
                    values["statementDate"] = .date(day)
                    values["dateApproximate"] = .checkbox(statement.isApproximate)
                }
                if !statement.locator.isEmpty { values["locator"] = .text(statement.locator) }
                if !statement.phase.isEmpty { values["phase"] = .text(statement.phase) }

                var notes: [String] = []
                if !statement.context.isEmpty { notes.append("Context: " + statement.context) }
                for (index, number) in statement.referenceNumbers.enumerated() {
                    let reference = references[number]
                    let id = try sourceID(
                        forReference: reference, trackID: trackID, cache: &sourceIDs,
                        actorID: actorID, fileName: fileName, at: nextDate(), summary: &summary
                    )
                    if index == 0, let id {
                        values["source"] = .relation(id)
                    } else {
                        notes.append("Also cited: " + Self.label(of: reference, number: number))
                    }
                }

                _ = try propose(
                    trackID: trackID, typeID: ItemType.statementID, title: title,
                    details: notes.joined(separator: "\n"), url: nil, classification: nil,
                    values: values, actorID: actorID, fileName: fileName, at: nextDate()
                )
                summary.statementsAdded += 1
            }
        }
        return summary
    }

    // MARK: Private

    private mutating func propose(
        trackID: UUID, typeID: UUID, title: String, details: String = "", url: URL?, classification: Classification?,
        values: [String: FieldValue], actorID: UUID, fileName: String, at date: Date
    ) throws -> Item {
        let type = try existingType(typeID)
        // A table may leave a required field empty; the student fills it in before approving.
        try validate(values, for: type, trackID: trackID, requireAll: false)
        let item = Item(
            trackID: trackID,
            kind: type.behavior,
            typeID: typeID,
            title: title,
            details: details,
            approval: .pending,
            creatorID: actorID,
            url: url,
            classification: classification,
            values: values,
            createdAt: date
        )
        items[item.id] = item
        record(.created, itemID: item.id, actorID: actorID, at: date, detail: "import:" + fileName)
        return item
    }

    /// The card for a reference: one that already exists, or a new one that waits for approval.
    /// `nil` when the reference has no usable link (a source needs one).
    private mutating func sourceID(
        forReference reference: ImportedReference?, trackID: UUID, cache: inout [Int: UUID],
        actorID: UUID, fileName: String, at date: Date, summary: inout ImportSummary
    ) throws -> UUID? {
        guard let reference, let url = reference.url else { return nil }
        if let cached = cache[reference.number] { return cached }
        if let existing = matchingSourceID(trackID: trackID, title: reference.title, url: url, urlIsExact: true) {
            cache[reference.number] = existing
            return existing
        }
        var values: [String: FieldValue] = [:]
        if !reference.authors.isEmpty { values["authors"] = .text(reference.authors) }
        if let year = reference.year { values["year"] = .number(Double(year)) }
        if !reference.venue.isEmpty { values["venue"] = .text(reference.venue) }
        if !reference.doi.isEmpty { values["doi"] = .text(reference.doi) }
        let item = try propose(
            trackID: trackID, typeID: ItemType.sourceID, title: reference.title, url: url,
            classification: nil, values: values, actorID: actorID, fileName: fileName, at: date
        )
        cache[reference.number] = item.id
        summary.sourcesAdded += 1
        return item.id
    }

    /// A source with the same title, or (when the link points at one page, not just a site) the same link.
    private func matchingSourceID(trackID: UUID, title: String, url: URL, urlIsExact: Bool) -> UUID? {
        items.values.first { item in
            guard item.trackID == trackID, item.kind == .source else { return false }
            if Self.same(item.title, title) { return true }
            return urlIsExact && url.path.count > 1 && item.url == url
        }?.id
    }

    private func statementExists(trackID: UUID, title: String, position: String) -> Bool {
        items.values.contains { item in
            guard item.trackID == trackID, item.kind == .statement else { return false }
            guard Self.same(item.title, title) else { return false }
            if case .text(let existing)? = item.values["position"] { return Self.same(existing, position) }
            return false
        }
    }

    /// Equal ignoring case, accents, extra spaces and line breaks (the same text laid out differently in
    /// another PDF, or typed again by hand).
    private static func same(_ a: String, _ b: String) -> Bool {
        func key(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        return key(a) == key(b)
    }

    private static func label(of reference: ImportedReference?, number: Int) -> String {
        guard let reference else { return "[\(number)]" }
        let year = reference.year.map { " (\($0))" } ?? ""
        return reference.title + year
    }
}
