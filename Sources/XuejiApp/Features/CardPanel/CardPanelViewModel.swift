import AppKit
import Foundation
import Observation
import XuejiCore

@Observable
final class CardPanelViewModel: ICardPanelView, ICardPanelController {
    private let store: AppStore

    /// Wired by the composition root: reads a source's PDF in the app.
    var readInApp: (UUID) -> Void = { _ in }

    init(store: AppStore) { self.store = store }

    func read(itemID: UUID) { readInApp(itemID) }

    func revealFile(itemID: UUID) {
        guard let url = store.workspace.items[itemID]?.url, url.isFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: ICardPanelView

    var content: CardPanelContent? {
        let workspace = store.workspace
        guard let id = store.focusedItemID,
              let item = workspace.items[id],
              let type = workspace.types[item.typeID] else { return nil }

        let fields = type.fields.map { field in
            CardPanelField(
                key: field.key,
                label: type.displayLabel(of: field),
                kind: field.kind,
                isRequired: field.isRequired,
                value: item.values[field.key],
                options: field.options.map { CardPanelOption(id: $0.key, label: type.displayLabel(of: $0, in: field)) },
                candidates: field.kind == .relation ? candidates(for: field, excluding: item) : []
            )
        }

        let linkedCards = workspace.items(referencing: item.id).map { linked -> CardPanelLinkedCard in
            let linkedType = workspace.types[linked.typeID]
            return CardPanelLinkedCard(
                id: linked.id,
                title: linked.title,
                typeName: linkedType?.displayName ?? "",
                symbol: linkedType?.symbol ?? "square.text.square"
            )
        }

        let comments = workspace.comments
            .filter { $0.itemID == id }
            .sorted { $0.createdAt < $1.createdAt }
            .map { CardPanelComment(id: $0.id, author: store.name(of: $0.authorID), text: $0.text, date: $0.createdAt) }

        let history = workspace.events
            .filter { $0.itemID == id }
            .sorted { $0.at > $1.at }
            .map { CardPanelHistoryLine(id: $0.id, text: describe($0), date: $0.at) }

        return CardPanelContent(
            itemID: item.id,
            typeName: type.displayName,
            typeSymbol: type.symbol,
            title: item.title,
            notes: item.notes,
            agentDetails: item.details,
            stage: item.stage,
            dueDay: item.dueDay,
            showsClassification: item.kind == .source || item.classification != nil,
            classification: item.classification,
            showsLink: item.kind == .source || item.url != nil,
            link: item.url?.absoluteString ?? "",
            linkIsFile: item.url?.isFileURL == true,
            origin: origin(of: item),
            assigneeName: item.assigneeID.map { store.name(of: $0) },
            fields: fields,
            linkedCards: linkedCards,
            comments: comments,
            history: history
        )
    }

    // MARK: ICardPanelController

    func rename(itemID: UUID, title: String) { store.rename(itemID, title: title) }
    func setNotes(itemID: UUID, text: String) { store.setNotes(itemID, text: text) }
    func setStage(itemID: UUID, stage: Stage) { store.move(itemID, to: stage) }
    func setDue(itemID: UUID, day: CalendarDay?) { store.setDue(itemID, day: day) }
    func setClassification(itemID: UUID, classification: Classification?) { store.setClassification(itemID, classification) }
    func addComment(itemID: UUID, text: String) { store.addComment(itemID, text: text) }
    func focus(itemID: UUID) { store.focus(itemID) }

    func setLink(itemID: UUID, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            store.setLink(itemID, url: nil)
        } else if let url = URL(string: clean) {
            store.setLink(itemID, url: url)
        } else {
            store.report(.invalidFieldValue)
        }
    }

    func setFieldText(itemID: UUID, key: String, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = fieldKind(itemID: itemID, key: key) else { return }
        if clean.isEmpty {
            store.setValue(itemID, key: key, value: nil)
            return
        }
        switch kind {
        case .number:
            if let number = Double(clean.replacingOccurrences(of: ",", with: ".")) {
                store.setValue(itemID, key: key, value: .number(number))
            } else {
                store.report(.invalidFieldValue)
            }
        case .url:
            if let url = URL(string: clean) {
                store.setValue(itemID, key: key, value: .url(url))
            } else {
                store.report(.invalidFieldValue)
            }
        default:
            store.setValue(itemID, key: key, value: .text(clean))
        }
    }

    func setFieldValue(itemID: UUID, key: String, value: FieldValue?) {
        store.setValue(itemID, key: key, value: value)
    }

    // MARK: Private

    private func fieldKind(itemID: UUID, key: String) -> FieldKind? {
        guard let item = store.workspace.items[itemID],
              let type = store.workspace.types[item.typeID] else { return nil }
        return type.fields.first { $0.key == key }?.kind
    }

    private func candidates(for field: FieldDefinition, excluding item: Item) -> [CardPanelOption] {
        let sameTrack = store.workspace.items.values.filter { $0.trackID == item.trackID && $0.approval == .approved }
        let allowed = sameTrack.filter { $0.id != item.id && (field.relatedTypeID == nil || $0.typeID == field.relatedTypeID) }
        let sorted = allowed.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return sorted.map { CardPanelOption(id: $0.id.uuidString, label: $0.title) }
    }

    private func origin(of item: Item) -> CardPanelOrigin {
        let members = store.workspace.members
        let creator = members[item.creatorID]
        let approval = store.workspace.events.last { $0.itemID == item.id && $0.kind == .approved }
        return CardPanelOrigin(
            isAgent: creator?.kind == .agent,
            name: store.name(of: item.creatorID),
            role: creator?.role ?? "",
            ownerName: creator?.ownerID.map { store.name(of: $0) },
            createdAt: item.createdAt,
            importedFrom: store.importedFileName(of: item),
            approvedByName: approval.map { store.name(of: $0.actorID) },
            approvedAt: approval?.at
        )
    }

    private func describe(_ event: Event) -> String {
        let action: String
        switch event.kind {
        case .created: action = L("event.created")
        case .approved: action = L("event.approved")
        case .rejected: action = L("event.rejected")
        case .moved: action = Lf("event.moved", Stage(rawValue: event.detail)?.title ?? event.detail)
        case .claimed: action = L("event.claimed")
        case .completed: action = L("event.completed")
        case .reviewRequested: action = L("event.reviewRequested")
        case .reviewResolved: action = L("event.reviewResolved")
        case .escalated: action = L("event.escalated")
        case .commented: action = L("event.commented")
        case .rescheduled: action = L("event.rescheduled")
        case .edited: action = L("event.edited")
        }
        return store.name(of: event.actorID) + " · " + action
    }
}
