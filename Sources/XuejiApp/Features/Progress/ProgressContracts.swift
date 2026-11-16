import Foundation
import XuejiCore

/// One draft in the writing list.
struct ProgressDraftRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let words: Int
}

/// Which of the two periods is meant.
enum ProgressSlot { case primary, comparison }

/// What the Progress screen may read.
protocol IProgressView {
    /// The period the numbers are about, and the one it is compared with (when comparing).
    var period: ProgressPeriod { get }
    var comparisonPeriod: ProgressPeriod { get }
    var isComparing: Bool { get }
    /// The two periods as stretches of time (the end is not included).
    var periodRange: DateInterval { get }
    var comparisonRange: DateInterval { get }
    var periodTotals: ProgressTotals { get }
    var comparisonTotals: ProgressTotals { get }
    /// Numbers for the open project, read from the history the app already keeps.
    var stats: ProgressStats { get }
    /// True while no card was ever finished and no proposal was ever decided.
    var hasNoHistory: Bool { get }
    /// The drafts of the project, longest first.
    var draftRows: [ProgressDraftRow] { get }
    var totalWords: Int { get }
}

/// What the Progress screen may trigger.
protocol IProgressController {
    func setPreset(_ preset: ProgressPreset, for slot: ProgressSlot)
    func setCustom(from: Date, to: Date, for slot: ProgressSlot)
    func setComparing(_ comparing: Bool)
    func openDraft(id: UUID)
}

typealias IProgressViewModel = IProgressView & IProgressController
