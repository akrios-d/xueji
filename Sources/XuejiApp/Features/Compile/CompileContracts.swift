import Foundation
import XuejiCore

/// One draft in the list on the left.
struct CompileSectionRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let words: Int
    let included: Bool
    /// 1 = chapter, 2 = section, 3 = subsection.
    let level: Int
}

/// What the compile screen may read.
protocol ICompileView {
    var title: String { get }
    /// In the order they appear in the document.
    var sections: [CompileSectionRow] { get }
    var style: CitationStyle { get }
    var includeBibliography: Bool { get }
    var includeUncited: Bool { get }
    var includeContents: Bool { get }
    /// The assembled document, rebuilt from the current choices.
    var document: CompiledDocument { get }
    /// True for a moment after the text was copied.
    var justCopied: Bool { get }
    /// What to check before exporting: unknown citation marks and sources with missing data.
    func warnings(for document: CompiledDocument) -> [String]
}

/// What the compile screen may trigger.
protocol ICompileController {
    func setTitle(_ title: String)
    func setStyle(_ style: CitationStyle)
    func setIncluded(_ included: Bool, draftID: UUID)
    func setLevel(_ level: Int, draftID: UUID)
    func move(draftID: UUID, by offset: Int)
    func moveSections(from source: IndexSet, to destination: Int)
    func setIncludeBibliography(_ value: Bool)
    func setIncludeUncited(_ value: Bool)
    func setIncludeContents(_ value: Bool)
    func includeAll(_ included: Bool)
    func openDraft(id: UUID)
    func copyAll()
    @MainActor func export(format: DraftFormat)
}

typealias ICompileViewModel = ICompileView & ICompileController
