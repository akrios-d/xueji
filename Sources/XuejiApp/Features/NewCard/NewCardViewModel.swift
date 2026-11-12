import Foundation
import Observation
import XuejiCore

@Observable
final class NewCardViewModel: INewCardView, INewCardController {
    private let store: AppStore
    private(set) var isPresented = false
    private(set) var selectedTypeID: UUID = ItemType.sourceID

    init(store: AppStore) { self.store = store }

    // MARK: INewCardView

    var types: [NewCardType] {
        let all = store.workspace.types.values
        let builtInOrder = [ItemType.sourceID, ItemType.statementID, ItemType.researchRequestID, ItemType.noteID]
        let builtIns = builtInOrder.compactMap { store.workspace.types[$0] }
        let custom = all
            .filter { !builtInOrder.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (builtIns + custom).map { NewCardType(id: $0.id, name: $0.displayName, symbol: $0.symbol) }
    }

    var requiresLink: Bool { store.workspace.types[selectedTypeID]?.behavior == .source }
    var isSource: Bool { requiresLink }

    var kinds: [NewCardOption] {
        guard let type = store.workspace.types[ItemType.sourceID],
              let field = type.fields.first(where: { $0.key == "sourceKind" }) else { return [] }
        return field.options.map { NewCardOption(id: $0.key, label: type.displayLabel(of: $0, in: field)) }
    }

    func canCreate(_ input: NewCardInput) -> Bool {
        guard !Self.clean(input.title).isEmpty else { return false }
        if requiresLink {
            guard Self.url(from: input.link) != nil else { return false }
            let year = Self.clean(input.year)
            return year.isEmpty || Self.year(from: year) != nil
        }
        return true
    }

    // MARK: INewCardController

    func present() { isPresented = true }
    func setPresented(_ isPresented: Bool) { self.isPresented = isPresented }
    func selectType(_ id: UUID) { selectedTypeID = id }

    func create(_ input: NewCardInput) {
        guard canCreate(input) else { return }
        let clean = Self.clean(input.title)
        var values: [String: FieldValue] = [:]
        if isSource {
            let authors = Self.clean(input.authors), venue = Self.clean(input.venue), doi = Self.clean(input.doi)
            if !authors.isEmpty { values["authors"] = .text(authors) }
            if !venue.isEmpty { values["venue"] = .text(venue) }
            if !doi.isEmpty { values["doi"] = .text(doi) }
            if let year = Self.year(from: Self.clean(input.year)) { values["year"] = .number(Double(year)) }
            if !input.kind.isEmpty { values["sourceKind"] = .select(input.kind) }
        }
        guard store.addCard(
            typeID: selectedTypeID, title: clean, url: Self.url(from: input.link),
            classification: isSource ? input.classification : nil, values: values
        ) != nil else { return }
        isPresented = false
        store.announce(Lf("inbox.created", clean))
    }

    // MARK: Private

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func year(from text: String) -> Int? {
        guard let year = Int(text), (1000...2200).contains(year) else { return nil }
        return year
    }

    /// Only web links count; the core rejects anything else, so the button stays off until it is valid.
    private static func url(from text: String) -> URL? {
        let clean = clean(text)
        guard let url = URL(string: clean), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
}
