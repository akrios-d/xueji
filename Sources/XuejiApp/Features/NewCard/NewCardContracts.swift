import Foundation
import XuejiCore

struct NewCardType: Identifiable, Hashable {
    let id: UUID
    let name: String
    let symbol: String
}

struct NewCardOption: Identifiable, Hashable {
    let id: String
    let label: String
}

/// Everything the form collects. The details after `link` only apply to sources.
struct NewCardInput: Equatable {
    var title = ""
    var link = ""
    /// Essential, complementary or secondary; none until the student decides.
    var classification: Classification?
    /// "Silva, João; Jones, Karl"
    var authors = ""
    /// Kept as text while typing; empty or a four-digit year.
    var year = ""
    var venue = ""
    var doi = ""
    /// The key of the "kind of source" option (journal article, book…); empty for none.
    var kind = ""
}

/// What the "new card" form may read.
protocol INewCardView {
    var isPresented: Bool { get }
    /// The types a card can be created as, the bibliography ones first.
    var types: [NewCardType] { get }
    var selectedTypeID: UUID { get }
    /// Sources need a web link; other types may have one.
    var requiresLink: Bool { get }
    /// Sources also take a classification, authors, year and the like.
    var isSource: Bool { get }
    /// The choices for "kind of source".
    var kinds: [NewCardOption] { get }
    func canCreate(_ input: NewCardInput) -> Bool
    /// The title of the card that is already in the project, while the student is being asked whether to add it again.
    var duplicateTitle: String? { get }
}

/// What the "new card" form may trigger.
protocol INewCardController {
    func present()
    func setPresented(_ isPresented: Bool)
    func selectType(_ id: UUID)
    /// Creates the card (it lands on the board) and closes the form.
    func create(_ input: NewCardInput)
    /// The answer "add it again" to the question about a card that already exists.
    func createAnyway(_ input: NewCardInput)
    func cancelDuplicate()
}

typealias INewCardViewModel = INewCardView & INewCardController
