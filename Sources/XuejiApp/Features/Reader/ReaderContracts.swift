import Foundation
import PDFKit
import XuejiCore

enum MarkKind: String, CaseIterable, Identifiable {
    case highlight, underline
    var id: String { rawValue }
}

/// One highlight or underline, which may span several lines of the page.
struct ReaderMark: Identifiable, Equatable {
    let id: String
    let kind: MarkKind
    /// "RRGGBB"
    let colorHex: String
    let pageLabel: String
    let quote: String
    let note: String
}

/// What the reader screen may read.
protocol IReaderView {
    var title: String { get }
    /// nil when the source is not a PDF on this Mac or could not be opened.
    var document: PDFDocument? { get }
    var versions: [ReadingVersion] { get }
    var currentVersion: ReadingVersion? { get }
    var marks: [ReaderMark] { get }
    /// Whether text is selected in the PDF (so it can be highlighted).
    var hasSelection: Bool { get }
    /// The colours to choose from, and the one in use.
    var colors: [MarkColor] { get }
    var markColor: MarkColor { get }
    var searchText: String { get }
    /// "2 of 7", "No matches", or nil when there is no search.
    var searchStatus: String? { get }
    var message: String? { get }
    /// Drafts a quote can be added to.
    var drafts: [Draft] { get }
}

/// What the reader screen may trigger.
protocol IReaderController {
    /// Gives the model the PDF view, to read its selection and move it.
    func attach(_ view: PDFView)
    func selectionChanged(hasSelection: Bool)
    func selectVersion(id: UUID)
    /// A copy of the current version for a topic; with or without its highlights.
    func createVersion(named name: String, keepHighlights: Bool)
    func renameCurrentVersion(to name: String)
    func deleteCurrentVersion()
    func mark(_ kind: MarkKind)
    func setMarkColor(_ color: MarkColor)
    /// Adds a colour of the student's own to the palette and starts using it.
    func addColor(name: String, hex: String)
    func renameColor(hex: String, to name: String)
    func removeColor(hex: String)
    func resetColors()
    func setNote(_ note: String, markID: String)
    func deleteMark(id: String)
    func show(markID: String)
    func copyQuote(markID: String)
    /// Appends the quote (with its page) to a draft and links the source to it; a new draft when `draftID` is nil.
    func addQuote(markID: String, toDraft draftID: UUID?)
    func setSearchText(_ text: String)
    func search()
    func nextMatch()
    func previousMatch()
    func dismissMessage()
    func close()
}

typealias IReaderViewModel = IReaderView & IReaderController
