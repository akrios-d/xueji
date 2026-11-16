import Foundation
import XuejiCore

/// One online reference as a task: done when its link opens.
struct LinkTask: Identifiable, Equatable {
    let id: Int
    let text: String
    let url: URL
    var status: LinkStatus = .pending
    /// The student confirmed it by hand (a site that refuses automatic visits, say).
    var confirmedByHand = false

    var isDone: Bool { status.isDone || confirmedByHand }
}

/// What the Links screen may read.
protocol ILinksView {
    var input: String { get }
    var tasks: [LinkTask] { get }
    /// References of the pasted list that have no link (not online, so not checked).
    var offlineCount: Int { get }
    var isChecking: Bool { get }
    /// False when the Mac has no internet connection; checking is then off.
    var isOnline: Bool { get }
    var doneCount: Int { get }
}

/// What the Links screen may trigger.
protocol ILinksController {
    func setInput(_ text: String)
    func check()
    /// Checks again the ones that are not done.
    func recheckOpen()
    func toggleConfirmed(_ id: Int)
    func openLink(_ id: Int)
    func clear()
}

typealias ILinksViewModel = ILinksView & ILinksController
