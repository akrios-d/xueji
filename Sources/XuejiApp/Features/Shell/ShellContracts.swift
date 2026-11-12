import Foundation
import XuejiCore

enum AppSection: Hashable {
    case board
    /// The board narrowed to one stage, for direct access from the sidebar.
    case stage(Stage)
    case calendar, inbox, writing, compile, triage, library
    /// Reading a PDF from the library; the sidebar keeps "Library" selected.
    case reader
}

/// What the app shell (sidebar and error banner) may read.
protocol IShellView {
    var selectedSection: AppSection { get }
    var pendingApprovalCount: Int { get }
    /// How many cards sit in a stage.
    func cardCount(in stage: Stage) -> Int
    var errorMessage: String? { get }
}

/// What the app shell may trigger.
protocol IShellController {
    func select(_ section: AppSection)
    func dismissError()
}

typealias IShellViewModel = IShellView & IShellController
