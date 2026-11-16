import SwiftUI
import XuejiCore

struct KanbanView: View {
    let viewModel: any IKanbanViewModel
    let panel: any ICardPanelViewModel
    /// Set when the sidebar opens one stage directly.
    let stage: Stage?
    @FocusState private var isBoardFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if viewModel.visibleStage != nil {
                // One stage: its column takes the whole width and lays the cards out in a grid.
                columnsRow
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView(.horizontal) {
                    columnsRow
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.sm)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            Text(L("board.hint"))
                .font(.caption)
                .foregroundStyle(Palette.ink3)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) { discardBanner }
        .focusable()
        .focused($isBoardFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { handle($0) }
        .onAppear {
            isBoardFocused = true
            viewModel.setVisibleStage(stage)
        }
        .onChange(of: stage) { _, newStage in viewModel.setVisibleStage(newStage) }
        .inspector(isPresented: panelBinding) {
            CardPanelView(viewModel: panel)
                .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        }
        .navigationTitle(stage?.title ?? viewModel.trackName)
        .searchable(text: searchBinding, placement: .toolbar, prompt: Text(L("board.search")))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { viewModel.setPanelShown(!viewModel.isPanelShown) } label: {
                    Label(viewModel.isPanelShown ? L("panel.hide") : L("panel.show"), systemImage: "sidebar.right")
                }
                .help(viewModel.isPanelShown ? L("panel.hide") : L("panel.show"))
                .keyboardShortcut("i", modifiers: .command)
                viewMenu
            }
        }
    }

    // MARK: Pieces

    private var columnsRow: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(viewModel.columns) { column in
                ColumnView(
                    column: column, viewModel: viewModel, isAlone: viewModel.visibleStage != nil,
                    onSelect: select, onOpen: open
                )
            }
        }
    }

    @ViewBuilder
    private var discardBanner: some View {
        if let message = viewModel.discardNotice {
            HStack(spacing: 10) {
                Image(systemName: "trash").foregroundStyle(Palette.ink3)
                Text(message).font(.callout).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer()
                Button(L("board.undo")) { viewModel.undoDiscard() }
                Button { viewModel.dismissDiscardNotice() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink3)
            }
            .padding(12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.trackName)
                .font(.screenTitle)
                .foregroundStyle(Palette.ink)
            HStack(spacing: 10) {
                ProgressBar(fraction: Double(viewModel.completedCount) / Double(max(viewModel.totalCount, 1)))
                Text(Lf("board.progress", viewModel.completedCount, viewModel.totalCount))
                    .font(.callout)
                    .foregroundStyle(Palette.ink2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    /// Filter and sort in one menu. Undo and redo live in the Board menu and on ⌘Z / ⇧⌘Z.
    private var viewMenu: some View {
        Menu {
            Picker(L("board.filter"), selection: filterBinding) {
                ForEach(KanbanFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Picker(L("board.sort"), selection: sortBinding) {
                ForEach(KanbanSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(
                L("board.view"),
                systemImage: viewModel.filter == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .help(L("board.view"))
    }

    // MARK: Bindings

    private var searchBinding: Binding<String> {
        Binding(get: { viewModel.searchText }, set: { viewModel.setSearchText($0) })
    }

    private var filterBinding: Binding<KanbanFilter> {
        Binding(get: { viewModel.filter }, set: { viewModel.setFilter($0) })
    }

    private var sortBinding: Binding<KanbanSort> {
        Binding(get: { viewModel.sort }, set: { viewModel.setSort($0) })
    }

    // MARK: Keyboard

    private var panelBinding: Binding<Bool> {
        Binding(get: { viewModel.isPanelShown }, set: { viewModel.setPanelShown($0) })
    }

    private func open(_ id: UUID) {
        select(id)
        viewModel.setPanelShown(true)
    }

    private func select(_ id: UUID) {
        viewModel.select(itemID: id)
        isBoardFocused = true
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.characters.lowercased() == "z", press.modifiers == .command {
            viewModel.undo()
            return .handled
        }
        if press.characters.lowercased() == "z", press.modifiers == [.command, .shift] {
            viewModel.redo()
            return .handled
        }
        guard press.modifiers.isEmpty else { return .ignored }
        switch press.key {
        case .leftArrow: viewModel.moveSelection(.left)
        case .rightArrow: viewModel.moveSelection(.right)
        case .upArrow: viewModel.moveSelection(.up)
        case .downArrow: viewModel.moveSelection(.down)
        case .return: viewModel.setPanelShown(true)
        case .escape: viewModel.select(itemID: nil)
        case .delete, .deleteForward: viewModel.discardSelected()
        default:
            // T / M / W set the deadline to today / tomorrow / next week; X removes it.
            switch press.characters.lowercased() {
            case "o": viewModel.openSelectedLink(); return .handled
            case "t": viewModel.setSelectedDue(inDays: 0); return .handled
            case "m": viewModel.setSelectedDue(inDays: 1); return .handled
            case "w": viewModel.setSelectedDue(inDays: 7); return .handled
            case "x": viewModel.setSelectedDue(inDays: nil); return .handled
            default: break
            }
            guard let digit = Int(press.characters),
                  (1...Stage.allCases.count).contains(digit) else { return .ignored }
            viewModel.moveSelected(to: Stage.allCases[digit - 1])
        }
        return .handled
    }
}

private struct ColumnView: View {
    let column: KanbanColumn
    let viewModel: any IKanbanViewModel
    /// A board narrowed to one stage: the column takes more room.
    let isAlone: Bool
    let onSelect: (UUID) -> Void
    let onOpen: (UUID) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollView {
                LazyVGrid(
                    columns: isAlone
                        ? [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 10, alignment: .top)]
                        : [GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(column.items) { item in
                        ItemCard(
                            item: item,
                            viewModel: viewModel,
                            isSelected: item.id == viewModel.selectedItemID,
                            onSelect: { onSelect(item.id) },
                            onOpen: { onOpen(item.id) }
                        )
                    }
                    if column.items.isEmpty { emptyState }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(minWidth: 292, idealWidth: 292, maxWidth: isAlone ? .infinity : 292)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            isTargeted ? Palette.accentLight : Palette.surfaceAlt,
            in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.accent.opacity(isTargeted ? 0.7 : 0), lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
        .animation(.easeInOut(duration: 0.2), value: column.items)
        .dropDestination(for: String.self, action: { ids, _ in
            for raw in ids {
                if let id = UUID(uuidString: raw) {
                    viewModel.move(itemID: id, to: column.stage)
                }
            }
            return !ids.isEmpty
        }, isTargeted: { isTargeted = $0 })
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: column.stage.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(column.stage.tint)
            Text(column.stage.title)
                .font(.heading(.headline))
                .foregroundStyle(Palette.ink)
            Text("\(column.items.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.ink2)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Palette.border.opacity(0.7), in: Capsule())
            Spacer()
            // Shown only while a card is selected: it is the key that moves that card here, and next to
            // the count it would otherwise read as a second number.
            if viewModel.selectedItemID != nil, !isAlone {
                KeyCap(label: "\(column.stage.shortcutDigit)")
                    .help(Lf("board.moveTo", column.stage.title))
            }
        }
        .padding(.horizontal, 4)
    }

    private var emptyState: some View {
        Text(L("board.empty"))
            .font(.callout)
            .foregroundStyle(Palette.ink3)
            .frame(maxWidth: .infinity, minHeight: 72)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
    }
}

private struct ItemCard: View {
    let item: Item
    let viewModel: any IKanbanViewModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    @State private var isHovering = false
    @State private var isPickingDate = false
    @State private var isRenaming = false
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 24, height: 24)
                    .background(Palette.accentLight, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                Text(item.title)
                    .font(.heading(.subheadline).weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            if !item.details.isEmpty {
                Text(item.details)
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                if let classification = item.classification {
                    ClassificationPill(classification: classification)
                }
                if viewModel.isAgentProposed(item) {
                    Label(L("board.byAgent"), systemImage: "sparkles")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Palette.ink2)
                }
                if let badge = viewModel.dueBadge(for: item) {
                    DueBadgeView(badge: badge)
                }
                Spacer(minLength: 0)
                if let assignee = viewModel.assigneeName(of: item) {
                    Label(assignee, systemImage: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(1)
                }
            }
            if let url = item.url {
                if url.isFileURL {
                    Button { viewModel.read(itemID: item.id) } label: {
                        Label(L("library.read"), systemImage: "book")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help(L("writing.basis.openPDF"))
                } else {
                    Link(url.host ?? url.absoluteString, destination: url)
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 2 : 1)
        )
        // Shadows only on interactive elevation, never decorative.
        .shadow(color: .black.opacity(isHovering ? 0.12 : 0), radius: isHovering ? 6 : 0, y: isHovering ? 2 : 0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .onHover { isHovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(perform: onSelect)
        .draggable(item.id.uuidString)
        .popover(isPresented: $isPickingDate, arrowEdge: .trailing) {
            DatePicker("", selection: dueBinding, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(12)
        }
        .sheet(isPresented: $isRenaming) { renameSheet }
        .contextMenu {
            Button(L("board.rename")) {
                newTitle = item.title
                isRenaming = true
            }
            Divider()
            ForEach(Stage.allCases, id: \.self) { stage in
                Button(Lf("board.moveTo", stage.title)) {
                    viewModel.move(itemID: item.id, to: stage)
                }
            }
            if !viewModel.otherProjects.isEmpty {
                Divider()
                Menu(L("project.copyTo")) {
                    ForEach(viewModel.otherProjects) { project in
                        Button(project.name) { viewModel.copy(itemID: item.id, toProject: project.id) }
                    }
                }
            }
            Divider()
            Button(L("board.discard"), role: .destructive) { viewModel.discard(itemID: item.id) }
            Divider()
            Button(L("due.menu.today")) { viewModel.setDue(itemID: item.id, inDays: 0) }
            Button(L("due.menu.tomorrow")) { viewModel.setDue(itemID: item.id, inDays: 1) }
            Button(L("due.menu.nextWeek")) { viewModel.setDue(itemID: item.id, inDays: 7) }
            Button(L("due.menu.pick")) { isPickingDate = true }
            if item.dueDay != nil {
                Button(L("due.menu.remove")) { viewModel.setDue(itemID: item.id, inDays: nil) }
            }
        }
    }

    private var renameSheet: some View {
        let save = {
            let clean = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { viewModel.rename(itemID: item.id, title: clean) }
            isRenaming = false
        }
        return VStack(alignment: .leading, spacing: 14) {
            Text(L("board.rename.title")).font(.headline)
            TextField(L("board.rename.placeholder"), text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button(L("reader.cancel")) { isRenaming = false }
                    .keyboardShortcut(.cancelAction)
                Button(L("board.rename.save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var dueBinding: Binding<Date> {
        Binding(
            get: { item.dueDay?.date() ?? Date() },
            set: { viewModel.setDue(itemID: item.id, day: CalendarDay($0)) }
        )
    }
}
