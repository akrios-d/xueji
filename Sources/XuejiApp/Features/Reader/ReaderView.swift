import AppKit
import PDFKit
import SwiftUI

/// Reads a PDF in the app: highlight, underline, notes, search, and one version of the file per topic.
struct ReaderView: View {
    let viewModel: any IReaderViewModel

    private enum Sheet: Identifiable {
        case newVersion, rename, colors
        var id: Self { self }
    }

    @State private var sheet: Sheet?
    /// The highlights panel starts closed so the PDF gets the whole width.
    @AppStorage("readerMarksShown") private var marksShown = false
    @State private var isConfirmingDelete = false
    @State private var isSearching = false

    private func focusSearch() {
        isSearching = false
        DispatchQueue.main.async { isSearching = true }
    }

    var body: some View {
        VStack(spacing: 0) {
            messageBanner
            if viewModel.document == nil {
                Text(L("reader.error.open")).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    PDFReaderRepresentable(viewModel: viewModel)
                    if marksShown {
                        Divider()
                        MarksPanel(viewModel: viewModel)
                            .frame(width: 300)
                    }
                }
            }
        }
        .background(Palette.bg)
        .navigationTitle(viewModel.title)
        .navigationSubtitle(viewModel.currentVersion?.name ?? "")
        .searchable(
            text: Binding(get: { viewModel.searchText }, set: { viewModel.setSearchText($0) }),
            isPresented: $isSearching,
            placement: .toolbar, prompt: Text(L("reader.search"))
        )
        .background {
            // ⌘F puts the cursor in the search field, also when it already is open but lost the focus.
            Button("") { focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
        .onSubmit(of: .search) { viewModel.search() }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { viewModel.close() } label: { Label(L("reader.back"), systemImage: "chevron.left") }
                    .help(L("reader.back"))
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { withAnimation(.easeInOut(duration: 0.15)) { marksShown.toggle() } } label: {
                    Label(marksShown ? L("reader.marks.hide") : L("reader.marks.show"), systemImage: "sidebar.right")
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .help((marksShown ? L("reader.marks.hide") : L("reader.marks.show")) + " (⌥⌘L)")
                versionMenu
                if let status = viewModel.searchStatus {
                    Text(status).font(.caption).foregroundStyle(Palette.ink3)
                    Button { viewModel.previousMatch() } label: { Image(systemName: "chevron.up") }
                    Button { viewModel.nextMatch() } label: { Image(systemName: "chevron.down") }
                }
                colorMenu
                Button { viewModel.mark(.highlight) } label: {
                    Label(L("reader.highlight"), systemImage: "highlighter")
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .help(L("reader.highlight") + " (⇧⌘H)")
                Button { viewModel.mark(.underline) } label: {
                    Label(L("reader.underline"), systemImage: "underline")
                }
                .help(L("reader.underline"))
                Button { viewModel.saveAsEvidenceQuote() } label: {
                    Label(L("reader.quote.save"), systemImage: "quote.opening")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!viewModel.hasSelection)
                .help(L("reader.quote.save.help") + " (⇧⌘E)")
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .colors:
                ColorsSheet(viewModel: viewModel, onDone: { self.sheet = nil })
            case .newVersion, .rename:
                VersionSheet(
                    isNew: sheet == .newVersion,
                    initialName: sheet == .rename ? (viewModel.currentVersion?.name ?? "") : "",
                    onDone: { name, keep in
                        if sheet == .newVersion {
                            viewModel.createVersion(named: name, keepHighlights: keep)
                        } else {
                            viewModel.renameCurrentVersion(to: name)
                        }
                        self.sheet = nil
                    },
                    onCancel: { self.sheet = nil }
                )
            }
        }
        .confirmationDialog(L("reader.deleteVersionTitle"), isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(L("reader.deleteVersion"), role: .destructive) { viewModel.deleteCurrentVersion() }
        }
    }

    // MARK: Pieces

    private var versionMenu: some View {
        Menu {
            ForEach(viewModel.versions) { version in
                Button {
                    viewModel.selectVersion(id: version.id)
                } label: {
                    if version.id == viewModel.currentVersion?.id {
                        Label(version.name, systemImage: "checkmark")
                    } else {
                        Text(version.name)
                    }
                }
            }
            Divider()
            Button(L("reader.newVersion")) { sheet = .newVersion }
            if viewModel.currentVersion?.isOriginal == false {
                Button(L("reader.renameVersion")) { sheet = .rename }
                Button(L("reader.deleteVersion"), role: .destructive) { isConfirmingDelete = true }
            }
        } label: {
            Label(viewModel.currentVersion?.name ?? L("reader.version"), systemImage: "doc.on.doc")
        }
        .help(L("reader.version.help"))
    }

    private var colorMenu: some View {
        Menu {
            ForEach(viewModel.colors) { color in
                Button { viewModel.setMarkColor(color) } label: {
                    HStack {
                        ColorDot.image(color.nsColor)
                        Text(color.displayName)
                        if color == viewModel.markColor { Image(systemName: "checkmark") }
                    }
                }
            }
            Divider()
            Button(L("reader.colors.manage")) { sheet = .colors }
        } label: {
            ColorDot.image(viewModel.markColor.nsColor, size: 16)
        }
        .help(L("reader.color") + ": " + viewModel.markColor.displayName)
    }

    @ViewBuilder
    private var messageBanner: some View {
        if let message = viewModel.message {
            HStack {
                Text(message).font(.callout).foregroundStyle(Palette.ink)
                Spacer()
                Button { viewModel.dismissMessage() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink3)
            }
            .padding(10)
            .background(Palette.surface)
        }
    }
}

// MARK: - PDF

private struct PDFReaderRepresentable: NSViewRepresentable {
    let viewModel: any IReaderViewModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = viewModel.document
        viewModel.attach(view)
        let model = viewModel
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: .PDFViewSelectionChanged, object: view, queue: .main
        ) { [weak view] _ in
            model.selectionChanged(hasSelection: view?.currentSelection?.string?.isEmpty == false)
        }
        context.coordinator.scrollObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewVisiblePagesChanged, object: view, queue: .main
        ) { [weak view] _ in
            guard let view, let document = view.document else { return }
            model.visiblePagesChanged(view.visiblePages.map { document.index(for: $0) })
        }
        // The first reading of the visible pages, before any scroll.
        DispatchQueue.main.async { [weak view] in
            guard let view, let document = view.document else { return }
            model.visiblePagesChanged(view.visiblePages.map { document.index(for: $0) })
        }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== viewModel.document {
            view.document = viewModel.document
            view.autoScales = true
            viewModel.attach(view)
        }
    }

    final class Coordinator {
        var observer: NSObjectProtocol?
        var scrollObserver: NSObjectProtocol?
        deinit {
            observer.map { NotificationCenter.default.removeObserver($0) }
            scrollObserver.map { NotificationCenter.default.removeObserver($0) }
        }
    }
}

// MARK: - Highlights panel

private struct MarksPanel: View {
    let viewModel: any IReaderViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(viewModel.markQuery.isEmpty
                     ? Lf("reader.marks", viewModel.marks.count)
                     : Lf("reader.marks.filtered", viewModel.shownMarks.count, viewModel.marks.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink2)
                Spacer()
                Toggle(L("reader.followScroll"), isOn: Binding(
                    get: { viewModel.followScroll }, set: { viewModel.setFollowScroll($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)
                .foregroundStyle(Palette.ink3)
                .help(L("reader.followScroll.help"))
            }
            .padding(14)
            Divider()
            if viewModel.marks.isEmpty {
                VStack(spacing: 8) {
                    Text(L("reader.noMarks.title")).font(.headline).foregroundStyle(Palette.ink)
                    Text(L("reader.noMarks.description"))
                        .font(.caption).foregroundStyle(Palette.ink3).multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.ink3)
                    TextField(L("reader.marks.search"), text: Binding(
                        get: { viewModel.markQuery }, set: { viewModel.setMarkQuery($0) }
                    ))
                    .textFieldStyle(.plain)
                    if !viewModel.markQuery.isEmpty {
                        Button { viewModel.setMarkQuery("") } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(Palette.ink3)
                    }
                }
                .padding(8)
                .background(Palette.bg, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12).padding(.vertical, 8)
                if viewModel.shownMarks.isEmpty {
                    Text(L("reader.marks.noMatch"))
                        .font(.caption).foregroundStyle(Palette.ink3)
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.shownMarks) { mark in
                                MarkRow(mark: mark, viewModel: viewModel)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Palette.ink3.opacity(0.5), lineWidth: viewModel.followScroll && viewModel.visiblePages.contains(mark.pageIndex) ? 1.5 : 0)
                                    )
                                    .id(mark.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: viewModel.focusedMarkID) { _, id in
                        guard viewModel.followScroll, viewModel.markQuery.isEmpty, let id else { return }
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) }
                    }
                }
            }
        }
        .background(Palette.surfaceAlt)
    }
}

private struct MarkRow: View {
    let mark: ReaderMark
    let viewModel: any IReaderViewModel
    @State private var note = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: mark.kind == .highlight ? "highlighter" : "underline")
                        .foregroundStyle(Color(nsColor: NSColor(hex: mark.colorHex) ?? .systemYellow))
                    Text(Lf("reader.page", mark.pageLabel)).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { viewModel.show(markID: mark.id) }
                .help(L("reader.showInPage"))
                Menu {
                    Button(L("reader.copyQuote")) { viewModel.copyQuote(markID: mark.id) }
                    Menu(L("reader.addToDraft")) {
                        Button(L("reader.newDraft")) { viewModel.addQuote(markID: mark.id, toDraft: nil) }
                        if !viewModel.drafts.isEmpty { Divider() }
                        ForEach(viewModel.drafts) { draft in
                            Button(draft.title.isEmpty ? L("writing.untitled") : draft.title) {
                                viewModel.addQuote(markID: mark.id, toDraft: draft.id)
                            }
                        }
                    }
                    Divider()
                    Button(L("reader.deleteMark"), role: .destructive) { viewModel.deleteMark(id: mark.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Text(mark.quote.isEmpty ? "…" : mark.quote)
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.show(markID: mark.id) }
                .help(L("reader.showInPage"))
            TextField(L("reader.note"), text: $note, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .focused($isEditing)
                .onSubmit { commit() }
        }
        .padding(10)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
        .onAppear { note = mark.note }
        .onChange(of: mark.note) { _, new in if !isEditing { note = new } }
        .onChange(of: isEditing) { _, editing in if !editing { commit() } }
    }

    /// The note is saved into the PDF when the field is left, not on every key.
    private func commit() {
        if note != mark.note { viewModel.setNote(note, markID: mark.id) }
    }
}

// MARK: - New version / rename

private struct VersionSheet: View {
    let isNew: Bool
    let initialName: String
    let onDone: (String, Bool) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var keepHighlights = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? L("reader.newVersion") : L("reader.renameVersion"))
                .font(.heading(.title3).weight(.semibold))
            Text(L("reader.version.topic")).font(.subheadline).foregroundStyle(Palette.ink2)
            TextField(L("reader.version.topicPlaceholder"), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(done)
            if isNew {
                Toggle(L("reader.version.keepHighlights"), isOn: $keepHighlights)
                Text(L("reader.version.help")).font(.caption).foregroundStyle(Palette.ink3)
            }
            HStack {
                Spacer()
                Button(L("reader.cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(isNew ? L("reader.create") : L("reader.save"), action: done)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { name = initialName }
    }

    private func done() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onDone(name, keepHighlights)
    }
}

// MARK: - Colours

enum ColorDot {
    /// A filled circle in the colour itself. Menus draw template images in one colour, so the image is made
    /// non-template and shown as it is.
    static func image(_ color: NSColor, size: CGFloat = 14) -> Image {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return Image(nsImage: image).renderingMode(.original)
    }
}

/// The student's palette: rename or remove colours, and add their own.
private struct ColorsSheet: View {
    let viewModel: any IReaderViewModel
    let onDone: () -> Void
    @State private var picked = Color.orange
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("reader.colors.title")).font(.heading(.title3).weight(.semibold))
            Text(L("reader.colors.help")).font(.caption).foregroundStyle(Palette.ink3)
            VStack(spacing: 6) {
                ForEach(viewModel.colors) { color in
                    HStack(spacing: 10) {
                        ColorDot.image(color.nsColor, size: 18)
                        TextField(L("reader.colors.name"), text: Binding(
                            get: { color.displayName }, set: { viewModel.renameColor(hex: color.hex, to: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        if color == viewModel.markColor {
                            Text(L("reader.colors.inUse")).font(.caption).foregroundStyle(Palette.ink3)
                        } else {
                            Button(L("reader.colors.use")) { viewModel.setMarkColor(color) }
                                .buttonStyle(.borderless)
                        }
                        Button(role: .destructive) { viewModel.removeColor(hex: color.hex) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.colors.count <= 1)
                        .help(L("reader.colors.remove"))
                    }
                }
            }
            Divider()
            Text(L("reader.colors.add")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2)
            HStack(spacing: 10) {
                ColorPicker("", selection: $picked, supportsOpacity: false).labelsHidden()
                TextField(L("reader.colors.newName"), text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button(L("reader.colors.addButton"), action: add).buttonStyle(.borderedProminent)
            }
            HStack {
                Button(L("reader.colors.reset")) { viewModel.resetColors() }
                Spacer()
                Button(L("reader.done"), action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func add() {
        guard let hex = NSColor(picked).hexString else { return }
        viewModel.addColor(name: newName, hex: hex)
        newName = ""
    }
}
