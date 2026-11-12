import SwiftUI
import XuejiCore

struct CalendarView: View {
    let viewModel: any ICalendarViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                weekdayHeader
                grid
                Text(L("calendar.hint"))
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .padding(.vertical, 10)
            }
            Divider()
            SidePanel(viewModel: viewModel)
                .frame(width: 320)
        }
        .background(Palette.bg)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { handle($0) }
        .onAppear { isFocused = true }
        .navigationTitle(viewModel.monthTitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { viewModel.showPreviousMonth() } label: {
                    Label(L("calendar.previousMonth"), systemImage: "chevron.left")
                }
                .help(L("calendar.previousMonth"))
                Button(L("calendar.today")) { viewModel.showToday() }
                Button { viewModel.showNextMonth() } label: {
                    Label(L("calendar.nextMonth"), systemImage: "chevron.right")
                }
                .help(L("calendar.nextMonth"))
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.weekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(viewModel.weeks) { week in
                HStack(spacing: 6) {
                    ForEach(week.cells) { cell in
                        DayCell(cell: cell, viewModel: viewModel)
                            .onTapGesture {
                                viewModel.select(day: cell.day)
                                isFocused = true
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .leftArrow: viewModel.moveSelection(byDays: -1)
        case .rightArrow: viewModel.moveSelection(byDays: 1)
        case .upArrow: viewModel.moveSelection(byDays: -7)
        case .downArrow: viewModel.moveSelection(byDays: 7)
        case .pageUp: viewModel.showPreviousMonth()
        case .pageDown: viewModel.showNextMonth()
        default:
            switch press.characters.lowercased() {
            case "t": viewModel.showToday()
            case "m": viewModel.setComposingMilestone(true)
            default: return .ignored
            }
        }
        return .handled
    }
}

private struct DayCell: View {
    let cell: CalendarDayCell
    let viewModel: any ICalendarViewModel

    private static let visibleEntries = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(cell.day.day)")
                .font(.system(.callout, design: .rounded).weight(cell.isToday ? .bold : .medium))
                .foregroundStyle(cell.isToday ? Palette.onAccent : (cell.isInMonth ? Palette.ink : Palette.ink3))
                .frame(minWidth: 24, minHeight: 24)
                .background(cell.isToday ? Palette.accent : Color.clear, in: Circle())
            ForEach(cell.entries.prefix(Self.visibleEntries)) { entry in
                EntryChip(entry: entry, isOverdue: viewModel.isOverdue(entry))
            }
            if cell.entries.count > Self.visibleEntries {
                Text(Lf("calendar.more", cell.entries.count - Self.visibleEntries))
                    .font(.caption2)
                    .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            cell.isSelected ? Palette.accentLight : (cell.isInMonth ? Palette.surface : Palette.surfaceAlt),
            in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(cell.isSelected ? Palette.accent : Palette.border, lineWidth: cell.isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: cell.isSelected)
    }
}

private struct EntryChip: View {
    let entry: AgendaEntry
    let isOverdue: Bool

    private var color: Color {
        if isOverdue { return Palette.danger }
        return entry.kind == .milestone ? Palette.accent : Palette.ink2
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(entry.title)
                .font(.caption2)
                .strikethrough(entry.isDone)
                .foregroundStyle(entry.isDone ? Palette.ink3 : Palette.ink)
                .lineLimit(1)
        }
    }
}

private struct SidePanel: View {
    let viewModel: any ICalendarViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.selectedDayTitle)
                        .font(.heading(.title3).weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Button { viewModel.setComposingMilestone(true) } label: {
                        Label(L("calendar.newMilestone"), systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .help(L("calendar.newMilestone"))
                    .popover(isPresented: composingBinding, arrowEdge: .bottom) {
                        NewMilestoneForm(viewModel: viewModel) { viewModel.setComposingMilestone(false) }
                    }
                }
                if viewModel.selectedEntries.isEmpty {
                    Text(L("calendar.nothing"))
                        .font(.callout)
                        .foregroundStyle(Palette.ink3)
                } else {
                    EntryList(entries: viewModel.selectedEntries, showDate: false, viewModel: viewModel)
                }
                if !viewModel.overdueEntries.isEmpty {
                    section(L("calendar.overdue"), entries: viewModel.overdueEntries)
                }
                if !viewModel.comingUpEntries.isEmpty {
                    section(L("calendar.comingUp"), entries: viewModel.comingUpEntries)
                }
            }
            .padding(20)
        }
        .background(Palette.surfaceAlt.opacity(0.5))
    }

    private var composingBinding: Binding<Bool> {
        Binding(get: { viewModel.isComposingMilestone }, set: { viewModel.setComposingMilestone($0) })
    }

    private func section(_ title: String, entries: [AgendaEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Palette.ink3)
            EntryList(entries: entries, showDate: true, viewModel: viewModel)
        }
    }
}

private struct EntryList: View {
    let entries: [AgendaEntry]
    let showDate: Bool
    let viewModel: any ICalendarViewModel

    var body: some View {
        VStack(spacing: 8) {
            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.kind == .milestone ? "flag.fill" : "checklist")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(viewModel.isOverdue(entry) ? Palette.danger : Palette.accent)
                        .frame(width: 22, height: 22)
                        .background(Palette.accentLight, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(entry.title)
                        .strikethrough(entry.isDone)
                        .foregroundStyle(entry.isDone ? Palette.ink3 : Palette.ink)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if showDate {
                        Text(viewModel.dateLabel(of: entry))
                            .font(.caption)
                            .foregroundStyle(viewModel.isOverdue(entry) ? Palette.danger : Palette.ink3)
                    }
                }
                .padding(10)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
                .contextMenu {
                    if entry.kind == .milestone {
                        Button(L("calendar.removeMilestone"), role: .destructive) {
                            viewModel.removeMilestone(id: entry.id)
                        }
                    }
                }
            }
        }
    }
}

private struct NewMilestoneForm: View {
    let viewModel: any ICalendarViewModel
    let onDone: () -> Void
    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(L("calendar.milestone.placeholder"), text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .focused($isFocused)
                .onSubmit(add)
            Button(L("board.add"), action: add)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canAddMilestone(titled: title))
        }
        .padding(14)
        .onAppear { isFocused = true }
    }

    private func add() {
        guard viewModel.canAddMilestone(titled: title) else { return }
        viewModel.addMilestone(title: title)
        onDone()
    }
}
