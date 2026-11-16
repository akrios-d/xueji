import SwiftUI
import XuejiCore

/// Puts drafts in order and builds the whole document, with citations and bibliography.
struct CompileView: View {
    let viewModel: any ICompileViewModel

    var body: some View {
        let sections = viewModel.sections
        let document = viewModel.document
        Group {
            if sections.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    controls(sections, document: document)
                        .frame(width: 340)
                    Divider()
                    preview(document, includedCount: sections.filter(\.included).count)
                }
            }
        }
        .background(Palette.bg)
        .navigationTitle(L("compile.title"))
        .navigationSubtitle(L("compile.subtitle"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { viewModel.copyAll() } label: {
                    Label(viewModel.justCopied ? L("compile.copied") : L("compile.copy"),
                          systemImage: viewModel.justCopied ? "checkmark" : "doc.on.clipboard")
                }
                .disabled(document.blocks.isEmpty)
                .help(L("compile.copy"))
                Menu {
                    ForEach(DraftFormat.allCases) { format in
                        Button(L("writing.export." + format.rawValue)) { viewModel.export(format: format) }
                    }
                } label: {
                    Label(L("compile.export"), systemImage: "square.and.arrow.up")
                }
                .disabled(document.blocks.isEmpty)
                .help(L("compile.export"))
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.ink3)
            Text(L("compile.noDrafts.title"))
                .font(.heading(.title2).weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(L("compile.noDrafts.description"))
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Left: drafts and options

    private func controls(_ sections: [CompileSectionRow], document: CompiledDocument) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(L("compile.titlePlaceholder"), text: Binding(
                get: { viewModel.title }, set: { viewModel.setTitle($0) }
            ))
            .textFieldStyle(.plain)
            .font(.heading(.title3).weight(.bold))
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            HStack {
                Text(L("compile.drafts")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2)
                Spacer()
                Menu {
                    Button(L("compile.includeAll")) { viewModel.includeAll(true) }
                    Button(L("compile.includeNone")) { viewModel.includeAll(false) }
                } label: {
                    Image(systemName: "checklist")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16).padding(.bottom, 2)
            Text(L("compile.outline.hint")).font(.caption).foregroundStyle(Palette.ink3)
                .padding(.horizontal, 16).padding(.bottom, 6)
            let numbers = outlineNumbers(sections)
            List {
                ForEach(sections) { row in
                    sectionRow(
                        row, number: numbers[row.id] ?? "",
                        isFirst: row.id == sections.first?.id, isLast: row.id == sections.last?.id
                    )
                }
                    .onMove { viewModel.moveSections(from: $0, to: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            Divider()
            options
            let notes = viewModel.warnings(for: document)
            if !notes.isEmpty { warnings(notes) }
        }
        .background(Palette.surfaceAlt.opacity(0.5))
    }

    /// "1", "1.1", "1.1.1"… for the drafts that are in the document: a section belongs to the chapter above it.
    private func outlineNumbers(_ rows: [CompileSectionRow]) -> [UUID: String] {
        var counters = [0, 0, 0]
        var result: [UUID: String] = [:]
        for row in rows where row.included {
            let level = min(max(row.level, 1), 3)
            counters[level - 1] += 1
            for deeper in level..<3 { counters[deeper] = 0 }
            result[row.id] = counters[0..<level].map { String(max($0, 0)) }.joined(separator: ".")
        }
        return result
    }

    private func sectionRow(_ row: CompileSectionRow, number: String, isFirst: Bool, isLast: Bool) -> some View {
        HStack(spacing: 8) {
            if row.level > 1 { Spacer().frame(width: CGFloat(row.level - 1) * 18) }
            Toggle("", isOn: Binding(
                get: { row.included }, set: { viewModel.setIncluded($0, draftID: row.id) }
            ))
            .labelsHidden()
            .help(L("compile.include"))
            VStack(alignment: .leading, spacing: 1) {
                Text(number.isEmpty ? row.title : "\(number)  \(row.title)")
                    .font(row.level == 1 ? .callout.weight(.semibold) : .callout)
                    .foregroundStyle(Palette.ink).lineLimit(1)
                Text(Lf("compile.words", row.words)).font(.caption2).foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 4)
            Picker("", selection: Binding(
                get: { row.level }, set: { viewModel.setLevel($0, draftID: row.id) }
            )) {
                ForEach(1...3, id: \.self) { level in Text(L("compile.level.\(level)")).tag(level) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(!row.included)
        }
        .opacity(row.included ? 1 : 0.55)
        .contextMenu {
            Button(L("compile.moveUp")) { viewModel.move(draftID: row.id, by: -1) }.disabled(isFirst)
            Button(L("compile.moveDown")) { viewModel.move(draftID: row.id, by: 1) }.disabled(isLast)
            Divider()
            Button(L("compile.openDraft")) { viewModel.openDraft(id: row.id) }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("compile.style"), selection: Binding(
                get: { viewModel.style }, set: { viewModel.setStyle($0) }
            )) {
                ForEach(CitationStyle.allCases) { style in Text(L("compile.style." + style.rawValue)).tag(style) }
            }
            .pickerStyle(.menu)
            Toggle(L("compile.bibliography"), isOn: Binding(
                get: { viewModel.includeBibliography }, set: { viewModel.setIncludeBibliography($0) }
            ))
            Toggle(L("compile.uncited"), isOn: Binding(
                get: { viewModel.includeUncited }, set: { viewModel.setIncludeUncited($0) }
            ))
            .disabled(!viewModel.includeBibliography)
            Toggle(L("compile.contents.option"), isOn: Binding(
                get: { viewModel.includeContents }, set: { viewModel.setIncludeContents($0) }
            ))
        }
        .font(.callout)
        .padding(16)
    }

    private func warnings(_ notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L("compile.warnings"), systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink2)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        Text(note).font(.caption).foregroundStyle(Palette.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 110)
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    // MARK: Right: the document

    private func preview(_ document: CompiledDocument, includedCount: Int) -> some View {
        VStack(spacing: 0) {
            Text(Lf("compile.summary", includedCount, document.wordCount, document.bibliography.count))
                .font(.caption)
                .foregroundStyle(Palette.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 8)
            Divider()
            if document.blocks.isEmpty {
                Text(L("compile.noneIncluded"))
                    .foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in blockView(block) }
                    }
                    .textSelection(.enabled)
                    .padding(32)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return Font.heading(.title).weight(.bold)
        case 2: return Font.heading(.title2).weight(.semibold)
        default: return Font.heading(.title3).weight(.semibold)
        }
    }

    @ViewBuilder
    private func blockView(_ block: DocumentBlock) -> some View {
        switch block {
        case .title(let text):
            Text(text).font(.heading(.largeTitle).weight(.bold)).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .center).padding(.bottom, 8)
        case .contents(let title, let hint):
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.heading(.title2).weight(.semibold)).foregroundStyle(Palette.ink)
                Text(hint).font(.caption).foregroundStyle(Palette.ink3)
            }
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level))
                .foregroundStyle(Palette.ink)
                .padding(.top, level == 1 ? 14 : 6)
        case .paragraph(let text):
            Text(MarkdownPreview.attributed(text)).font(.body).foregroundStyle(Palette.ink).lineSpacing(4)
        case .reference(let text):
            Text(text).font(.callout).foregroundStyle(Palette.ink2)
                .padding(.leading, 20)
        }
    }
}
