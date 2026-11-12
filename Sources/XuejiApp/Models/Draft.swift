import Foundation

/// A piece of free text the student writes in the app, to copy into Word or anywhere else.
/// Drafts are not cards: they never go through the Inbox or onto the board.
struct Draft: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var text: String
    /// What the text is based on, in the student's own words.
    var basis: String
    /// Cards (sources, statements, tasks…) the text is based on.
    var linkedItemIDs: [UUID]
    var updatedAt: Date
    /// The project the draft belongs to; nil in files saved before there were projects (they go to the first one).
    var trackID: UUID?

    init(
        id: UUID = UUID(), title: String = "", text: String = "", basis: String = "",
        linkedItemIDs: [UUID] = [], updatedAt: Date = Date(), trackID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.basis = basis
        self.linkedItemIDs = linkedItemIDs
        self.updatedAt = updatedAt
        self.trackID = trackID
    }
}
