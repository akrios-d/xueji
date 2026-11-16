import Foundation
import Observation
import XuejiCore

@Observable
final class ShellViewModel: IShellView, IShellController {
    private let store: AppStore
    private(set) var selectedSection: AppSection = .board

    init(store: AppStore) { self.store = store }

    // MARK: IShellView

    var pendingApprovalCount: Int { store.workspace.pendingApprovals().count }
    var errorMessage: String? { store.errorMessage }
    func cardCount(in stage: Stage) -> Int { store.stageCount(stage) }

    // MARK: IShellController

    /// The screen the reader was opened from, so closing it goes back there.
    private var sectionBeforeReader: AppSection?

    func select(_ section: AppSection) {
        if section == .reader, selectedSection != .reader { sectionBeforeReader = selectedSection }
        selectedSection = section
    }

    func closeReader() {
        let target = sectionBeforeReader ?? .library
        sectionBeforeReader = nil
        selectedSection = target == .reader ? .library : target
    }
    func dismissError() { store.dismissError() }
}
