import SwiftUI
import UniformTypeIdentifiers
import XuejiCore

/// The inbox: where new work is created (a card, or a PDF import) and where everything an agent or an import
/// produced waits for a human decision.
struct InboxView: View {
    let viewModel: any IInboxViewModel
    let newCard: any INewCardViewModel
    @FocusState private var isFocused: Bool
    @State private var bulk: Bulk?

    private enum Bulk: Identifiable {
        case approve, discard
        var id: Self { self }
    }

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if viewModel.pendingApprovals.isEmpty && viewModel.isFiltering {
                                VStack(spacing: 8) {
                                    Text(L("inbox.noMatches")).foregroundStyle(Palette.ink2)
                                    Button(L("inbox.clearFilters")) { viewModel.clearFilters() }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }
                            if !viewModel.pendingApprovals.isEmpty {
                                SectionHeader(
                                    title: viewModel.isFiltering
                                        ? Lf("inbox.showing", viewModel.pendingApprovals.count, viewModel.totalPending)
                                        : L("inbox.toApprove")
                                )
                                ForEach(viewModel.pendingApprovals) { item in
                                    ApprovalCard(
                                        item: item,
                                        viewModel: viewModel,
                                        isSelected: item.id == viewModel.selectedItemID,
                                        onSelect: {
                                            viewModel.select(itemID: item.id)
                                            isFocused = true
                                        }
                                    )
                                }
                            }
                            if !viewModel.itemsNeedingHuman.isEmpty {
                                SectionHeader(title: L("inbox.reviewsExhausted"))
                                    .padding(.top, 8)
                                ForEach(viewModel.itemsNeedingHuman) { item in
                                    Label(item.title, systemImage: "exclamationmark.bubble")
                                        .foregroundStyle(Palette.ink)
                                        .padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
                                }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    Text(L("inbox.hint"))
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                        .padding(.vertical, 10)
                }
            }
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { importBanner }
        .searchable(text: searchBinding, placement: .toolbar, prompt: Text(L("inbox.search")))
        .confirmationDialog(bulkTitle, isPresented: bulkBinding, titleVisibility: .visible) {
            Button(bulk == .approve ? L("inbox.bulk.approveAction") : L("inbox.bulk.discardAction"),
                   role: bulk == .discard ? .destructive : nil) {
                if bulk == .approve { viewModel.approveShown() } else { viewModel.rejectShown() }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { viewModel.undo() } label: {
                    Label(L("undo.button"), systemImage: "arrow.uturn.backward")
                }
                .disabled(viewModel.undoLabel == nil)
                .help(viewModel.undoLabel.map { Lf("undo.undo", $0) + " (⌘Z)" } ?? L("undo.nothing"))
                Button { viewModel.redo() } label: {
                    Label(L("redo.button"), systemImage: "arrow.uturn.forward")
                }
                .disabled(viewModel.redoLabel == nil)
                .help(viewModel.redoLabel.map { Lf("undo.redo", $0) + " (⇧⌘Z)" } ?? L("redo.nothing"))
                filterMenu
                sortMenu
                Menu {
                    Button(L("inbox.bulk.approve")) { bulk = .approve }
                    Button(L("inbox.bulk.discard"), role: .destructive) { bulk = .discard }
                } label: {
                    Label(L("inbox.bulk"), systemImage: "checklist")
                }
                .disabled(viewModel.pendingApprovals.isEmpty)
                .help(L("inbox.bulk.help"))
                Menu {
                    Button(L("card.new")) { newCard.present() }
                    Divider()
                    Button(L("inbox.import.auto")) { viewModel.requestImport(nil) }
                } label: {
                    Label(L("inbox.add"), systemImage: "plus")
                }
                .help(L("inbox.add.help"))
                .popover(isPresented: newCardBinding, arrowEdge: .bottom) {
                    NewCardView(viewModel: newCard)
                }
            }
        }
        .fileImporter(isPresented: chooserBinding, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { viewModel.importPDF(at: url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let pdf = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
            viewModel.dropPDF(at: pdf)
            return true
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { handle($0) }
        .onAppear {
            isFocused = true
            viewModel.moveSelection(by: 0)
        }
        .navigationTitle(L("inbox.title"))
        .navigationSubtitle(L("inbox.subtitle"))
        .animation(.easeInOut(duration: 0.2), value: viewModel.pendingApprovals)
    }

    private var newCardBinding: Binding<Bool> {
        Binding(get: { newCard.isPresented }, set: { newCard.setPresented($0) })
    }

    /// Centered, with the three ways to start laid out in one tidy row.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.ink3)
            Text(L("inbox.empty.title"))
                .font(.heading(.title2).weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(L("inbox.empty.description"))
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button(L("card.new")) { newCard.present() }
                .buttonStyle(.borderedProminent)
            VStack(spacing: 8) {
                importOption(L("inbox.import.auto"), detail: L("inbox.import.auto.detail"), symbol: "wand.and.stars") {
                    viewModel.requestImport(nil)
                }
            }
            .frame(maxWidth: 460)
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func importOption(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Palette.ink)
                    Text(detail).font(.caption).foregroundStyle(Palette.ink3)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchBinding: Binding<String> {
        Binding(get: { viewModel.searchText }, set: { viewModel.setSearchText($0) })
    }

    private var bulkBinding: Binding<Bool> {
        Binding(get: { bulk != nil }, set: { if !$0 { bulk = nil } })
    }

    private var bulkTitle: String {
        let count = viewModel.pendingApprovals.count
        return bulk == .discard ? Lf("inbox.bulk.discardTitle", count) : Lf("inbox.bulk.approveTitle", count)
    }

    private var filterMenu: some View {
        Menu {
            Picker(L("inbox.filter.kind"), selection: Binding(get: { viewModel.kindFilter }, set: { viewModel.setKindFilter($0) })) {
                ForEach(InboxKind.allCases) { Text(L("inbox.kind." + $0.rawValue)).tag($0) }
            }
            .pickerStyle(.inline)
            Picker(L("inbox.filter.classification"), selection: Binding(
                get: { viewModel.classificationFilter }, set: { viewModel.setClassificationFilter($0) }
            )) {
                Text(L("inbox.classification.all")).tag(Classification?.none)
                ForEach([Classification.essential, .complementary, .secondary], id: \.self) {
                    Text($0.title).tag(Classification?.some($0))
                }
            }
            .pickerStyle(.inline)
            if !viewModel.origins.isEmpty {
                Picker(L("inbox.filter.origin"), selection: Binding(
                    get: { viewModel.originFilter }, set: { viewModel.setOriginFilter($0) }
                )) {
                    Text(L("inbox.origin.all")).tag(String?.none)
                    ForEach(viewModel.origins, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.inline)
            }
            if viewModel.isFiltering {
                Divider()
                Button(L("inbox.clearFilters")) { viewModel.clearFilters() }
            }
        } label: {
            Label(
                L("board.filter"),
                systemImage: viewModel.isFiltering
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help(L("board.filter"))
    }

    private var sortMenu: some View {
        Menu {
            Picker(L("board.sort"), selection: Binding(get: { viewModel.sort }, set: { viewModel.setSort($0) })) {
                ForEach(InboxSort.allCases) { Text(L("inbox.sort." + $0.rawValue)).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(L("board.sort"), systemImage: "arrow.up.arrow.down.circle")
        }
        .help(L("board.sort"))
    }

    private var chooserBinding: Binding<Bool> {
        Binding(get: { viewModel.isChoosingFile }, set: { viewModel.setChoosingFile($0) })
    }

    @ViewBuilder
    private var importBanner: some View {
        if let message = viewModel.notice {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.pos)
                Text(message).font(.callout).foregroundStyle(Palette.ink)
                Spacer()
                Button { viewModel.dismissNotice() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink3)
                    .help(L("inbox.dismiss"))
            }
            .padding(12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
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
        case .upArrow: viewModel.moveSelection(by: -1)
        case .downArrow: viewModel.moveSelection(by: 1)
        case .return: viewModel.approveSelected()
        case .delete: viewModel.rejectSelected()
        default:
            switch press.characters.lowercased() {
            case "a": viewModel.approveSelected()
            case "d": viewModel.rejectSelected()
            default: return .ignored
            }
        }
        return .handled
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink3)
    }
}

private struct ApprovalCard: View {
    let item: Item
    let viewModel: any IInboxViewModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 24, height: 24)
                    .background(Palette.accentLight, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                Text(item.title).font(.heading(.headline)).foregroundStyle(Palette.ink)
                Spacer()
                if let position = viewModel.readingOrder(of: item) {
                    Text(Lf("inbox.readingOrder", position))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Palette.surfaceAlt, in: Capsule())
                }
                if let classification = item.classification {
                    ClassificationPill(classification: classification)
                }
            }
            if !item.details.isEmpty {
                Text(item.details).foregroundStyle(Palette.ink2)
            }
            if let classification = item.classification {
                Text(classification.summary)
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
            }
            if let url = item.url {
                Link(url.absoluteString, destination: url).font(.caption)
            }
            HStack {
                Text(viewModel.originLine(of: item))
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                Spacer()
                Button(L("inbox.reject")) { viewModel.reject(itemID: item.id) }
                    .buttonStyle(.bordered)
                Button(L("inbox.approve")) { viewModel.approve(itemID: item.id) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 2 : 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onTapGesture(perform: onSelect)
    }
}
