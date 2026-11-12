import Foundation

extension Workspace {
    // MARK: - Types (humans only)

    @discardableResult
    public mutating func addType(
        name: String,
        symbol: String = "square.text.square",
        fields: [FieldDefinition] = [],
        agentsMayPropose: Bool = false,
        by actorID: UUID
    ) throws -> ItemType {
        try requireHuman(actorID)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw XuejiError.emptyText }
        var accepted: [FieldDefinition] = []
        for field in fields {
            try validateDefinition(field, among: accepted)
            accepted.append(field)
        }
        let type = ItemType(
            name: cleanName, symbol: symbol, behavior: .custom,
            fields: accepted, agentsMayPropose: agentsMayPropose
        )
        types[type.id] = type
        return type
    }

    /// Adds a field to any type, built-in or not. Existing items simply have no value for it, so a
    /// required field can only be added while no item uses the type.
    @discardableResult
    public mutating func addField(typeID: UUID, field: FieldDefinition, by actorID: UUID) throws -> ItemType {
        try requireHuman(actorID)
        var type = try existingType(typeID)
        try validateDefinition(field, among: type.fields)
        if field.isRequired, items.values.contains(where: { $0.typeID == typeID }) {
            throw XuejiError.invalidFieldDefinition
        }
        type.fields.append(field)
        types[typeID] = type
        return type
    }

    /// Adds a choice to a select field (for example a new kind of actor).
    @discardableResult
    public mutating func addOption(typeID: UUID, fieldKey: String, option: FieldOption, by actorID: UUID) throws -> ItemType {
        try requireHuman(actorID)
        var type = try existingType(typeID)
        guard let index = type.fields.firstIndex(where: { $0.key == fieldKey }) else { throw XuejiError.fieldNotFound }
        let field = type.fields[index]
        guard field.kind == .select || field.kind == .multiSelect else { throw XuejiError.invalidFieldDefinition }
        guard Self.isValidKey(option.key) else { throw XuejiError.invalidFieldKey }
        guard !field.options.contains(where: { $0.key == option.key }) else { throw XuejiError.duplicateFieldKey }
        guard !option.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw XuejiError.emptyText }
        type.fields[index].options.append(option)
        types[typeID] = type
        return type
    }

    // MARK: - Values

    /// Sets (or, with `nil`, clears) one field of an item. Humans only; an agent supplies its values
    /// when it creates the item, and a human can correct them before approving.
    @discardableResult
    public mutating func setFieldValue(
        itemID: UUID,
        key: String,
        to value: FieldValue?,
        by actorID: UUID,
        at now: Date = Date()
    ) throws -> Item {
        try requireHuman(actorID)
        var item = try existingItem(itemID)
        let type = try existingType(item.typeID)
        guard let field = type.fields.first(where: { $0.key == key }) else { throw XuejiError.fieldNotFound }
        if let value {
            try check(value, against: field, trackID: item.trackID)
            item.values[key] = value
        } else {
            if field.isRequired { throw XuejiError.requiredFieldMissing }
            item.values.removeValue(forKey: key)
        }
        items[itemID] = item
        record(.edited, itemID: itemID, actorID: actorID, at: now, detail: key)
        return item
    }

    // MARK: - Queries

    /// Approved items that point at `itemID` through a relation field (for example the statements of a source).
    public func items(referencing itemID: UUID) -> [Item] {
        items.values
            .filter { $0.approval == .approved && $0.values.values.contains(.relation(itemID)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Helpers (shared with Workspace.swift)

    func existingType(_ id: UUID) throws -> ItemType {
        guard let found = types[id] else { throw XuejiError.typeNotFound }
        return found
    }

    func validate(_ values: [String: FieldValue], for type: ItemType, trackID: UUID, requireAll: Bool) throws {
        for (key, value) in values {
            guard let field = type.fields.first(where: { $0.key == key }) else { throw XuejiError.fieldNotFound }
            try check(value, against: field, trackID: trackID)
        }
        guard requireAll else { return }
        for field in type.fields where field.isRequired {
            guard let value = values[field.key], !Self.isEmpty(value) else { throw XuejiError.requiredFieldMissing }
        }
    }

    // MARK: - Private

    private func requireHuman(_ actorID: UUID) throws {
        guard try activeMember(actorID).kind == .human else { throw XuejiError.notPermitted }
    }

    private func check(_ value: FieldValue, against field: FieldDefinition, trackID: UUID) throws {
        switch (field.kind, value) {
        case (.text, .text), (.longText, .text), (.checkbox, .checkbox), (.date, .date):
            return
        case (.number, .number(let number)):
            guard number.isFinite else { throw XuejiError.invalidFieldValue }
        case (.url, .url(let url)):
            guard Self.isWebURL(url) else { throw XuejiError.invalidFieldValue }
        case (.select, .select(let key)):
            guard field.options.contains(where: { $0.key == key }) else { throw XuejiError.invalidFieldValue }
        case (.multiSelect, .multiSelect(let keys)):
            let known = Set(field.options.map(\.key))
            guard Set(keys).count == keys.count, keys.allSatisfy(known.contains) else { throw XuejiError.invalidFieldValue }
        case (.relation, .relation(let id)):
            guard let target = items[id], target.trackID == trackID else { throw XuejiError.invalidFieldValue }
            if let related = field.relatedTypeID, target.typeID != related { throw XuejiError.invalidFieldValue }
        default:
            throw XuejiError.invalidFieldValue
        }
    }

    private func validateDefinition(_ field: FieldDefinition, among existing: [FieldDefinition]) throws {
        guard Self.isValidKey(field.key) else { throw XuejiError.invalidFieldKey }
        guard !existing.contains(where: { $0.key == field.key }) else { throw XuejiError.duplicateFieldKey }
        guard !field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw XuejiError.emptyText }
        switch field.kind {
        case .select, .multiSelect:
            let keys = field.options.map(\.key)
            guard !keys.isEmpty,
                  keys.allSatisfy(Self.isValidKey),
                  Set(keys).count == keys.count,
                  field.options.allSatisfy({ !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  field.relatedTypeID == nil
            else { throw XuejiError.invalidFieldDefinition }
        case .relation:
            guard field.options.isEmpty else { throw XuejiError.invalidFieldDefinition }
            if let related = field.relatedTypeID, types[related] == nil { throw XuejiError.invalidFieldDefinition }
        default:
            guard field.options.isEmpty, field.relatedTypeID == nil else { throw XuejiError.invalidFieldDefinition }
        }
    }

    private static func isEmpty(_ value: FieldValue) -> Bool {
        switch value {
        case .text(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .multiSelect(let keys): return keys.isEmpty
        default: return false
        }
    }

    /// Lowercase letters, digits and underscores, starting with a letter, at most 40 characters.
    static func isValidKey(_ key: String) -> Bool {
        key.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) != nil
    }
}
