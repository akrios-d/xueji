import Foundation
import Observation
import XuejiCore

@Observable
final class ProgressViewModel: IProgressView, IProgressController {
    private let store: AppStore

    /// Wired by the composition root: shows a draft in the Writing screen.
    var showDraft: (UUID) -> Void = { _ in }

    init(store: AppStore) { self.store = store }

    private(set) var period = ProgressPeriod(.last30Days)
    private(set) var comparisonPeriod = ProgressPeriod(.previous)
    private(set) var isComparing = false
    private let calendar = Calendar.current

    // MARK: IProgressView

    var periodRange: DateInterval { period.interval(calendar: calendar) }

    var comparisonRange: DateInterval {
        comparisonPeriod.interval(calendar: calendar, reference: periodRange)
    }

    var periodTotals: ProgressTotals {
        store.workspace.progressTotals(trackID: store.trackID, in: periodRange, calendar: calendar)
    }

    var comparisonTotals: ProgressTotals {
        store.workspace.progressTotals(trackID: store.trackID, in: comparisonRange, calendar: calendar)
    }

    var stats: ProgressStats { store.workspace.progress(trackID: store.trackID) }

    var hasNoHistory: Bool {
        let value = stats
        return value.totalFinished == 0 && value.approved + value.rejected == 0
            && value.weeks.allSatisfy { $0.created == 0 }
    }

    var draftRows: [ProgressDraftRow] {
        store.drafts
            .map { ProgressDraftRow(
                id: $0.id, title: $0.title.isEmpty ? L("writing.untitled") : $0.title,
                words: $0.text.split(whereSeparator: { $0.isWhitespace }).count
            ) }
            .sorted { $0.words > $1.words }
    }

    var totalWords: Int { draftRows.reduce(0) { $0 + $1.words } }

    // MARK: IProgressController

    func setPreset(_ preset: ProgressPreset, for slot: ProgressSlot) {
        switch slot {
        case .primary:
            // "Previous" only makes sense as the second period.
            guard preset != .previous else { return }
            period.preset = preset
        case .comparison:
            comparisonPeriod.preset = preset
        }
    }

    func setCustom(from: Date, to: Date, for slot: ProgressSlot) {
        switch slot {
        case .primary: period = ProgressPeriod(.custom, from: from, to: to)
        case .comparison: comparisonPeriod = ProgressPeriod(.custom, from: from, to: to)
        }
    }

    func setComparing(_ comparing: Bool) { isComparing = comparing }

    func openDraft(id: UUID) { showDraft(id) }
}
