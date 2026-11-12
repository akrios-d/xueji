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

    func select(_ section: AppSection) { selectedSection = section }
    func dismissError() { store.dismissError() }
}
