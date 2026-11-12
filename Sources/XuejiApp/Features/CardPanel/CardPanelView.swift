import SwiftUI
import XuejiCore

/// The side panel of a card: its properties, your notes, the fields of its type, comments and history.
struct CardPanelView: View {
    let viewModel: any ICardPanelViewModel

    var body: some View {
        Group {
            if let content = viewModel.content {
                PanelBody(content: content, viewModel: viewModel)
                    // A new card starts with fresh drafts; unsaved ones are saved as the old one disappears.
                    .id(content.itemID)
            } else {
                ContentUnavailableView(
                    L("panel.empty.title"),
                    systemImage: "sidebar.right",
                    description: Text(L("panel.empty.description"))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg)
    }
}

// MARK: - Body

private struct PanelBody: View {
    let content: CardPanelContent
    let viewModel: any ICardPanelViewModel

    private static let classifications: [Classification] = [.essential, .complementary, .secondary]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                properties
                notes
                if !content.agentDetails.isEmpty { agentDetails }
                if !content.fields.isEmpty { fields }
                if !content.linkedCards.isEmpty { linkedCards }
                comments
                history
            }
            .padding(20)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(content.typeName, systemImage: content.typeSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.accent)
            DraftTextField(
                text: content.title,
                placeholder: L("panel.titlePlaceholder"),
                axis: .vertical,
                font: .heading(.title2).weight(.semibold),
                isPlain: true
            ) { viewModel.rename(itemID: content.itemID, title: $0) }
        }
    }

    // MARK: Properties

    private var properties: some View {
        VStack(spacing: 0) {
            PropertyRow(label: L("panel.stage")) {
                Picker("", selection: stageBinding) {
                    ForEach(Stage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            PropertyRow(label: L("panel.due")) {
                if content.dueDay != nil {
                    DatePicker("", selection: dueBinding, displayedComponents: .date)
                        .labelsHidden()
                    Button(L("panel.due.remove")) { viewModel.setDue(itemID: content.itemID, day: nil) }
                        .buttonStyle(.borderless)
                } else {
                    Button(L("panel.due.add")) { viewModel.setDue(itemID: content.itemID, day: CalendarDay(Date())) }
                        .buttonStyle(.borderless)
                }
            }
            if content.showsClassification {
                PropertyRow(label: L("panel.classification")) { classificationMenu }
                if let classification = content.classification {
                    Text(classification.summary)
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 6)
                }
            }
            if content.showsLink {
                PropertyRow(label: L("panel.link")) {
                    if content.linkIsFile {
                        Button { viewModel.read(itemID: content.itemID) } label: {
                            Label(L("library.read"), systemImage: "book")
                        }
                        .buttonStyle(.bordered)
                        Button { viewModel.revealFile(itemID: content.itemID) } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help(L("panel.link.reveal"))
                        Spacer(minLength: 0)
                    } else {
                    DraftTextField(text: content.link, placeholder: L("panel.link.placeholder")) {
                        viewModel.setLink(itemID: content.itemID, text: $0)
                    }
                    if !content.link.isEmpty, let url = URL(string: content.link) {
                        Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                            .help(L("shortcuts.openLink"))
                    }
                    }
                }
            }
            if let assignee = content.assigneeName {
                PropertyRow(label: L("panel.assignee")) { Text(assignee).foregroundStyle(Palette.ink) }
            }
            originRows
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
    }

    /// Where the card came from: a person or an agent, which one, and when.
    @ViewBuilder
    private var originRows: some View {
        let origin = content.origin
        PropertyRow(label: L("panel.origin")) {
            VStack(alignment: .leading, spacing: 2) {
                Label(origin.name, systemImage: origin.isAgent ? "sparkles" : "person.crop.circle")
                    .foregroundStyle(Palette.ink)
                Text(originCaption(origin))
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
            }
        }
        PropertyRow(label: L("panel.created")) {
            Text(origin.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localization.locale))).foregroundStyle(Palette.ink)
        }
        if origin.isAgent || origin.importedFrom != nil, let approver = origin.approvedByName, let date = origin.approvedAt {
            PropertyRow(label: L("panel.approved")) {
                Text(Lf("panel.approvedBy", approver, date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localization.locale))))
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    private func originCaption(_ origin: CardPanelOrigin) -> String {
        if let file = origin.importedFrom { return Lf("panel.origin.importedFrom", file) }
        guard origin.isAgent else { return L("panel.origin.human") }
        if let owner = origin.ownerName { return Lf("panel.origin.agentOf", origin.role, owner) }
        return L("panel.origin.agent")
    }

    private var classificationMenu: some View {
        Menu {
            Button(L("panel.none")) { viewModel.setClassification(itemID: content.itemID, classification: nil) }
            Divider()
            ForEach(Self.classifications, id: \.self) { classification in
                Button {
                    viewModel.setClassification(itemID: content.itemID, classification: classification)
                } label: {
                    Text(classification.title)
                }
                .help(classification.summary)
            }
        } label: {
            if let classification = content.classification {
                ClassificationPill(classification: classification)
            } else {
                Text(L("panel.none")).foregroundStyle(Palette.ink3)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var stageBinding: Binding<Stage> {
        Binding(
            get: { content.stage },
            set: { viewModel.setStage(itemID: content.itemID, stage: $0) }
        )
    }

    private var dueBinding: Binding<Date> {
        Binding(
            get: { content.dueDay?.date() ?? Date() },
            set: { viewModel.setDue(itemID: content.itemID, day: CalendarDay($0)) }
        )
    }

    // MARK: Notes, agent text and fields

    private var notes: some View {
        Block(title: L("panel.notes")) {
            DraftTextEditor(text: content.notes, placeholder: L("panel.notes.placeholder")) {
                viewModel.setNotes(itemID: content.itemID, text: $0)
            }
        }
    }

    private var agentDetails: some View {
        Block(title: L("panel.details")) {
            Text(content.agentDetails)
                .font(.callout)
                .foregroundStyle(Palette.ink2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private var fields: some View {
        Block(title: L("panel.fields")) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(content.fields) { field in
                    FieldRow(field: field, itemID: content.itemID, viewModel: viewModel)
                }
            }
        }
    }

    // MARK: Linked cards, comments, history

    private var linkedCards: some View {
        Block(title: L("panel.linked")) {
            VStack(spacing: 8) {
                ForEach(content.linkedCards) { card in
                    Button { viewModel.focus(itemID: card.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: card.symbol)
                                .foregroundStyle(Palette.accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.title).foregroundStyle(Palette.ink).lineLimit(2)
                                Text(card.typeName).font(.caption).foregroundStyle(Palette.ink3)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var comments: some View {
        Block(title: L("panel.comments")) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(content.comments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(comment.author).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
                            Text(comment.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localization.locale)))
                                .font(.caption)
                                .foregroundStyle(Palette.ink3)
                        }
                        Text(comment.text).font(.callout).foregroundStyle(Palette.ink2).textSelection(.enabled)
                    }
                }
                CommentComposer { viewModel.addComment(itemID: content.itemID, text: $0) }
            }
        }
    }

    private var history: some View {
        DisclosureGroup(L("panel.history")) {
            VStack(spacing: 6) {
                ForEach(content.history) { line in
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.text).font(.caption).foregroundStyle(Palette.ink2)
                        Spacer(minLength: 8)
                        Text(line.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localization.locale)))
                            .font(.caption)
                            .foregroundStyle(Palette.ink3)
                    }
                }
            }
            .padding(.top, 6)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Palette.ink3)
    }
}

// MARK: - Pieces

private struct Block<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Palette.ink3)
            content
        }
    }
}

private struct PropertyRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(Palette.ink3)
                .frame(width: 96, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

/// One field of the card's type, drawn for the kind of field it is.
private struct FieldRow: View {
    let field: CardPanelField
    let itemID: UUID
    let viewModel: any ICardPanelViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.isRequired ? field.label + " *" : field.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.ink3)
            control
        }
    }

    @ViewBuilder
    private var control: some View {
        switch field.kind {
        case .text, .number, .url:
            DraftTextField(text: textValue, placeholder: "") {
                viewModel.setFieldText(itemID: itemID, key: field.key, text: $0)
            }
        case .longText:
            DraftTextEditor(text: textValue, placeholder: "") {
                viewModel.setFieldText(itemID: itemID, key: field.key, text: $0)
            }
        case .date:
            dateControl
        case .checkbox:
            Toggle("", isOn: checkboxBinding).labelsHidden()
        case .select:
            Picker("", selection: selectBinding) {
                Text(L("panel.none")).tag(String?.none)
                ForEach(field.options) { Text($0.label).tag(String?.some($0.id)) }
            }
            .labelsHidden()
            .fixedSize()
        case .multiSelect:
            multiSelectControl
        case .relation:
            Picker("", selection: relationBinding) {
                Text(L("panel.none")).tag(String?.none)
                ForEach(field.candidates) { Text($0.label).tag(String?.some($0.id)) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    // MARK: Values

    private var textValue: String {
        switch field.value {
        case .text(let text)?: return text
        case .url(let url)?: return url.absoluteString
        case .number(let number)?: return Self.numberText(number)
        default: return ""
        }
    }

    private static func numberText(_ number: Double) -> String {
        if number == number.rounded(), abs(number) < 1e15 { return String(Int(number)) }
        return String(number)
    }

    private var selectedKeys: [String] {
        if case .multiSelect(let keys)? = field.value { return keys }
        return []
    }

    // MARK: Controls

    private var dateControl: some View {
        HStack {
            if case .date(let day)? = field.value {
                DatePicker("", selection: dateBinding(for: day), displayedComponents: .date).labelsHidden()
                Button(L("panel.due.remove")) {
                    viewModel.setFieldValue(itemID: itemID, key: field.key, value: nil)
                }
                .buttonStyle(.borderless)
            } else {
                Button(L("panel.date.set")) {
                    viewModel.setFieldValue(itemID: itemID, key: field.key, value: .date(CalendarDay(Date())))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var multiSelectControl: some View {
        Menu {
            ForEach(field.options) { option in
                Toggle(option.label, isOn: Binding(
                    get: { selectedKeys.contains(option.id) },
                    set: { isOn in
                        var keys = selectedKeys
                        if isOn { keys.append(option.id) } else { keys.removeAll { $0 == option.id } }
                        viewModel.setFieldValue(itemID: itemID, key: field.key, value: keys.isEmpty ? nil : .multiSelect(keys))
                    }
                ))
            }
        } label: {
            let labels = field.options.filter { selectedKeys.contains($0.id) }.map(\.label)
            Text(labels.isEmpty ? L("panel.none") : labels.joined(separator: ", "))
                .foregroundStyle(labels.isEmpty ? Palette.ink3 : Palette.ink)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: Bindings

    private func dateBinding(for day: CalendarDay) -> Binding<Date> {
        Binding(
            get: { day.date() },
            set: { viewModel.setFieldValue(itemID: itemID, key: field.key, value: .date(CalendarDay($0))) }
        )
    }

    private var checkboxBinding: Binding<Bool> {
        Binding(
            get: { field.value == .checkbox(true) },
            set: { viewModel.setFieldValue(itemID: itemID, key: field.key, value: .checkbox($0)) }
        )
    }

    private var selectBinding: Binding<String?> {
        Binding(
            get: {
                if case .select(let key)? = field.value { return key }
                return nil
            },
            set: { new in
                viewModel.setFieldValue(itemID: itemID, key: field.key, value: new.map { FieldValue.select($0) })
            }
        )
    }

    private var relationBinding: Binding<String?> {
        Binding(
            get: {
                if case .relation(let id)? = field.value { return id.uuidString }
                return nil
            },
            set: { new in
                let target = new.flatMap { UUID(uuidString: $0) }
                viewModel.setFieldValue(itemID: itemID, key: field.key, value: target.map { FieldValue.relation($0) })
            }
        )
    }
}

/// A one-line (or wrapping) text field that saves when you press return or leave it, not on every key.
private struct DraftTextField: View {
    let text: String
    let placeholder: String
    var axis: Axis = .horizontal
    var font: Font = .body
    var isPlain = false
    let onCommit: (String) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        text: String,
        placeholder: String,
        axis: Axis = .horizontal,
        font: Font = .body,
        isPlain: Bool = false,
        onCommit: @escaping (String) -> Void
    ) {
        self.text = text
        self.placeholder = placeholder
        self.axis = axis
        self.font = font
        self.isPlain = isPlain
        self.onCommit = onCommit
        _draft = State(initialValue: text)
    }

    var body: some View {
        field
            .font(font)
            .foregroundStyle(Palette.ink)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onChange(of: text) { _, new in
                if !isFocused { draft = new }
            }
            .onDisappear(perform: commit)
    }

    @ViewBuilder
    private var field: some View {
        if isPlain {
            TextField(placeholder, text: $draft, axis: axis).textFieldStyle(.plain)
        } else {
            TextField(placeholder, text: $draft, axis: axis).textFieldStyle(.roundedBorder)
        }
    }

    private func commit() {
        if draft != text { onCommit(draft) }
    }
}

/// A multi-line editor that saves when you leave it or when the panel moves to another card.
private struct DraftTextEditor: View {
    let text: String
    let placeholder: String
    let onCommit: (String) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(text: String, placeholder: String, onCommit: @escaping (String) -> Void) {
        self.text = text
        self.placeholder = placeholder
        self.onCommit = onCommit
        _draft = State(initialValue: text)
    }

    var body: some View {
        TextEditor(text: $draft)
            .font(.body)
            .foregroundStyle(Palette.ink)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .frame(minHeight: 96)
            .padding(6)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(alignment: .topLeading) {
                if draft.isEmpty && !placeholder.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Palette.ink3)
                        .padding(.top, 14)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isFocused ? Palette.accent : Palette.border)
            )
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
            .onChange(of: text) { _, new in
                if !isFocused { draft = new }
            }
            .onDisappear(perform: commit)
    }

    private func commit() {
        if draft != text { onCommit(draft) }
    }
}

private struct CommentComposer: View {
    let onPost: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField(L("panel.comment.placeholder"), text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(post)
            Button(L("panel.comment.post"), action: post)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func post() {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        onPost(clean)
        text = ""
    }
}
