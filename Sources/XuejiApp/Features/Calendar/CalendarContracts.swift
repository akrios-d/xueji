import Foundation
import XuejiCore

struct CalendarDayCell: Identifiable {
    let day: CalendarDay
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let entries: [AgendaEntry]
    var id: CalendarDay { day }
}

struct CalendarWeek: Identifiable {
    let id: Int
    let cells: [CalendarDayCell]
}

/// What the calendar screen may read.
protocol ICalendarView {
    var monthTitle: String { get }
    var weekdaySymbols: [String] { get }
    var weeks: [CalendarWeek] { get }
    var selectedDay: CalendarDay { get }
    var selectedDayTitle: String { get }
    var selectedEntries: [AgendaEntry] { get }
    var overdueEntries: [AgendaEntry] { get }
    /// Deadlines and milestones in the next two weeks, starting today.
    var comingUpEntries: [AgendaEntry] { get }
    var isComposingMilestone: Bool { get }
    func isOverdue(_ entry: AgendaEntry) -> Bool
    func dateLabel(of entry: AgendaEntry) -> String
    func canAddMilestone(titled title: String) -> Bool
}

/// What the calendar screen may trigger.
protocol ICalendarController {
    func showPreviousMonth()
    func showNextMonth()
    func showToday()
    func select(day: CalendarDay)
    func moveSelection(byDays days: Int)
    func addMilestone(title: String)
    func removeMilestone(id: UUID)
    func setComposingMilestone(_ isComposing: Bool)
}

typealias ICalendarViewModel = ICalendarView & ICalendarController
