import Foundation
import Observation
import XuejiCore

@Observable
final class CalendarViewModel: ICalendarView, ICalendarController {
    private let store: AppStore
    private let calendar = Calendar.current

    private(set) var selectedDay: CalendarDay
    /// The first day of the month shown in the grid.
    private(set) var visibleMonth: CalendarDay
    private(set) var isComposingMilestone = false

    init(store: AppStore) {
        self.store = store
        self.selectedDay = store.today
        self.visibleMonth = store.today.startOfMonth
    }

    // MARK: ICalendarView

    var monthTitle: String {
        visibleMonth.date(in: calendar).formatted(.dateTime.month(.wide).year().locale(Localization.locale))
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var weeks: [CalendarWeek] {
        let first = visibleMonth
        let firstDate = first.date(in: calendar)
        let weekday = calendar.component(.weekday, from: firstDate)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstDate)?.count ?? 30
        let weekCount = (offset + daysInMonth + 6) / 7
        let start = first.adding(days: -offset, in: calendar)
        let end = start.adding(days: weekCount * 7 - 1, in: calendar)
        let entries = Dictionary(
            grouping: store.workspace.agenda(trackID: store.trackID, from: start, through: end),
            by: \.day
        )
        let today = store.today
        return (0..<weekCount).map { week in
            CalendarWeek(id: week, cells: (0..<7).map { column in
                let day = start.adding(days: week * 7 + column, in: calendar)
                return CalendarDayCell(
                    day: day,
                    isInMonth: day.month == first.month,
                    isToday: day == today,
                    isSelected: day == selectedDay,
                    entries: entries[day] ?? []
                )
            })
        }
    }

    var selectedDayTitle: String {
        selectedDay.date(in: calendar).formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Localization.locale))
    }

    var selectedEntries: [AgendaEntry] {
        store.workspace.agenda(trackID: store.trackID, from: selectedDay, through: selectedDay)
    }

    var overdueEntries: [AgendaEntry] {
        store.workspace.overdue(trackID: store.trackID, today: store.today)
    }

    var comingUpEntries: [AgendaEntry] {
        let today = store.today
        return store.workspace.agenda(trackID: store.trackID, from: today, through: today.adding(days: 14, in: calendar))
    }

    func isOverdue(_ entry: AgendaEntry) -> Bool {
        entry.kind == .itemDue && !entry.isDone && entry.day < store.today
    }

    func dateLabel(of entry: AgendaEntry) -> String {
        switch entry.day.days(until: store.today, in: calendar) {
        case 0: return L("due.today")
        case -1: return L("due.tomorrow")
        default: return entry.day.date(in: calendar).formatted(.dateTime.day().month(.abbreviated).locale(Localization.locale))
        }
    }

    func canAddMilestone(titled title: String) -> Bool {
        !Self.clean(title).isEmpty
    }

    // MARK: ICalendarController

    func showPreviousMonth() {
        visibleMonth = visibleMonth.adding(months: -1, in: calendar).startOfMonth
    }

    func showNextMonth() {
        visibleMonth = visibleMonth.adding(months: 1, in: calendar).startOfMonth
    }

    func showToday() {
        select(day: store.today)
    }

    func select(day: CalendarDay) {
        selectedDay = day
        visibleMonth = day.startOfMonth
    }

    func moveSelection(byDays days: Int) {
        select(day: selectedDay.adding(days: days, in: calendar))
    }

    func addMilestone(title: String) {
        guard canAddMilestone(titled: title) else { return }
        store.addMilestone(title: Self.clean(title), day: selectedDay)
    }

    func removeMilestone(id: UUID) {
        store.removeMilestone(id)
    }

    func setComposingMilestone(_ isComposing: Bool) {
        isComposingMilestone = isComposing
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
