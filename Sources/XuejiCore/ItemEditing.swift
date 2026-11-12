import Foundation

extension Workspace {
    /// Only humans edit a card's own properties. They may do it before approving an agent's proposal,
    /// to correct it first.

    @discardableResult
    public mutating func renameItem(itemID: UUID, to title: String, by actorID: UUID, at now: Date = Date()) throws -> Item {
        var item = try humanEditableItem(itemID, actorID)
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw XuejiError.emptyText }
        item.title = clean
        items[itemID] = item
        record(.edited, itemID: itemID, actorID: actorID, at: now, detail: "title")
        return item
    }

    /// The student's own notes. Saved on every change, so it records no history entry.
    @discardableResult
    public mutating func setNotes(itemID: UUID, to notes: String, by actorID: UUID) throws -> Item {
        var item = try humanEditableItem(itemID, actorID)
        item.notes = notes
        items[itemID] = item
        return item
    }

    @discardableResult
    public mutating func setClassification(
        itemID: UUID, to classification: Classification?, by actorID: UUID, at now: Date = Date()
    ) throws -> Item {
        var item = try humanEditableItem(itemID, actorID)
        item.classification = classification
        items[itemID] = item
        record(.edited, itemID: itemID, actorID: actorID, at: now, detail: "classification")
        return item
    }

    /// Changing the link clears "link verified": nobody has checked the new one.
    @discardableResult
    public mutating func setLink(itemID: UUID, to url: URL?, by actorID: UUID, at now: Date = Date()) throws -> Item {
        var item = try humanEditableItem(itemID, actorID)
        if let url {
            guard Self.isSourceLocation(url) else { throw XuejiError.invalidFieldValue }
        } else if item.kind == .source {
            throw XuejiError.sourceRequiresValidURL
        }
        item.url = url
        item.linkVerifiedAt = nil
        items[itemID] = item
        record(.edited, itemID: itemID, actorID: actorID, at: now, detail: "link")
        return item
    }

    private func humanEditableItem(_ itemID: UUID, _ actorID: UUID) throws -> Item {
        guard try activeMember(actorID).kind == .human else { throw XuejiError.notPermitted }
        return try existingItem(itemID)
    }
}
