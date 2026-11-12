import Foundation

/// One copy of a PDF with its own highlights, kept for a topic or a use ("Securitization chapter").
/// The first version of every PDF is the original file itself.
struct ReadingVersion: Identifiable, Equatable, Codable {
    let id: UUID
    let itemID: UUID
    var name: String
    let fileURL: URL
    let createdAt: Date
    let isOriginal: Bool
}
