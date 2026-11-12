import Foundation
import XuejiCore

/// What the writing screen may read.
protocol IWritingView {
    /// Newest first.
    var drafts: [Draft] { get }
    var selectedDraft: Draft? { get }
    /// True for a moment after the text was copied.
    var justCopied: Bool { get }
    /// The title of the draft just deleted, while it can still be brought back.
    var deletedDraftTitle: String? { get }
    func wordCount(of draft: Draft) -> Int
    func characterCount(of draft: Draft) -> Int
    /// The cards the draft is based on (cards that were removed since are left out).
    func linkedCards(of draft: Draft) -> [Item]
    /// Cards that could be added as a basis, filtered by `query`.
    func candidateCards(for draft: Draft, matching query: String) -> [Item]
    /// "Authors · year" for a source, the kind of card otherwise.
    func detail(of item: Item) -> String
    /// The free-text notes of "Based on", one per line.
    func notes(of draft: Draft) -> [String]
    /// Sources can be cited with a mark like [@Silva2020]; other cards cannot.
    func canCite(_ item: Item) -> Bool
    /// Whether opening this card shows a PDF in the reader (instead of the board).
    func opensInReader(_ item: Item) -> Bool
    /// Where the last source search found its phrase.
    var sourceHits: [SourceHit] { get }
    var isSearchingSources: Bool { get }
    /// The phrase `sourceHits` answers; empty when there is no search.
    var searchedPhrase: String { get }
}

/// What the writing screen may trigger.
protocol IWritingController {
    func newDraft()
    func select(draftID: UUID?)
    func setTitle(_ title: String, draftID: UUID)
    func setText(_ text: String, draftID: UUID)
    /// Puts the draft's text on the clipboard as plain text.
    func copy(draftID: UUID)
    func delete(draftID: UUID)
    func undoDelete()
    func dismissDeleteNotice()
    func setBasis(_ text: String, draftID: UUID)
    func addNote(_ text: String, draftID: UUID)
    func removeNote(at index: Int, draftID: UUID)
    func link(cardID: UUID, draftID: UUID)
    func unlink(cardID: UUID, draftID: UUID)
    /// Opens the card on the board.
    func showCard(itemID: UUID)
    /// Puts the citation mark of a source on the clipboard, to paste where it belongs in the text.
    func copyCitation(cardID: UUID)
    /// Looks for a phrase in the notes, cards and PDFs the draft is based on (the results arrive in `sourceHits`).
    func searchSources(_ query: String, draftID: UUID)
    func clearSourceSearch()
    /// Opens the place of a hit: the PDF at that page with the phrase marked, or the card.
    func open(hit: SourceHit)
    /// Appends the excerpt to the text as a quote with its source and page.
    func insertQuote(hit: SourceHit, draftID: UUID)
    /// Copies the text followed by what it is based on.
    func copyWithSources(draftID: UUID)
    /// Saves the draft as a Word, rich text or plain text file (the user picks where).
    @MainActor func export(draftID: UUID, format: DraftFormat)
}

typealias IWritingViewModel = IWritingView & IWritingController
