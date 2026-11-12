import AppKit
import Foundation
import Observation
import XuejiCore

@Observable
final class CompileViewModel: ICompileView, ICompileController {
    private let store: AppStore
    private(set) var justCopied = false
    private var copyToken = 0

    /// Wired by the composition root: shows a draft in the Writing screen.
    var showDraft: (UUID) -> Void = { _ in }

    init(store: AppStore) { self.store = store }

    // MARK: The list

    /// The stored order without the drafts that were deleted, plus new drafts at the end (not included).
    private var effectiveSections: [CompilationSection] {
        let existing = Set(store.drafts.map(\.id))
        var result = store.compilation.sections.filter { existing.contains($0.id) }
        let known = Set(result.map(\.id))
        for draft in store.drafts.sorted(by: { $0.updatedAt < $1.updatedAt }) where !known.contains(draft.id) {
            result.append(CompilationSection(id: draft.id))
        }
        return result
    }

    private func change(_ body: (inout [CompilationSection]) -> Void) {
        var list = effectiveSections
        body(&list)
        store.updateCompilation { $0.sections = list }
    }

    // MARK: ICompileView

    var title: String { store.compilation.title }
    var style: CitationStyle { store.compilation.style }
    var includeBibliography: Bool { store.compilation.includeBibliography }
    var includeUncited: Bool { store.compilation.includeUncited }
    var includeContents: Bool { store.compilation.includeContents }

    var sections: [CompileSectionRow] {
        let drafts = Dictionary(uniqueKeysWithValues: store.drafts.map { ($0.id, $0) })
        return effectiveSections.compactMap { section in
            drafts[section.id].map { draft in
                CompileSectionRow(
                    id: draft.id,
                    title: draft.title.isEmpty ? L("writing.untitled") : draft.title,
                    words: draft.text.split(whereSeparator: { $0.isWhitespace }).count,
                    included: section.included,
                    level: section.level
                )
            }
        }
    }

    var document: CompiledDocument {
        let drafts = Dictionary(uniqueKeysWithValues: store.drafts.map { ($0.id, $0) })
        let parts = effectiveSections.filter(\.included).compactMap { section in
            drafts[section.id].map { draft in
                CompileSection(
                    heading: draft.title.isEmpty ? L("writing.untitled") : draft.title,
                    level: section.level, text: draft.text, linked: draft.linkedItemIDs
                )
            }
        }
        let options = store.compilation
        return DocumentCompiler.compile(
            title: options.title, sections: parts, references: store.references(), style: options.style,
            includeUncited: options.includeUncited, includeBibliography: options.includeBibliography,
            contents: options.includeContents ? (L("compile.contents"), L("compile.contents.hint")) : nil,
            referencesHeading: L("compile.references")
        )
    }

    func warnings(for document: CompiledDocument) -> [String] {
        var lines = document.unknownKeys.map { Lf("compile.warning.unknown", $0) }
        for item in document.incomplete {
            let title = store.workspace.items[item.id]?.title ?? "—"
            let missing = item.missing.map { L("compile.missing." + $0) }.joined(separator: ", ")
            lines.append(Lf("compile.warning.incomplete", title, missing))
        }
        return lines
    }

    // MARK: ICompileController

    func setTitle(_ title: String) { store.updateCompilation { $0.title = title } }
    func setStyle(_ style: CitationStyle) { store.updateCompilation { $0.style = style } }
    func setIncludeBibliography(_ value: Bool) { store.updateCompilation { $0.includeBibliography = value } }
    func setIncludeUncited(_ value: Bool) { store.updateCompilation { $0.includeUncited = value } }
    func setIncludeContents(_ value: Bool) { store.updateCompilation { $0.includeContents = value } }

    func setIncluded(_ included: Bool, draftID: UUID) {
        change { list in
            if let index = list.firstIndex(where: { $0.id == draftID }) { list[index].included = included }
        }
    }

    func setLevel(_ level: Int, draftID: UUID) {
        change { list in
            if let index = list.firstIndex(where: { $0.id == draftID }) { list[index].level = min(max(level, 1), 3) }
        }
    }

    func includeAll(_ included: Bool) {
        change { list in for index in list.indices { list[index].included = included } }
    }

    func move(draftID: UUID, by offset: Int) {
        change { list in
            guard let index = list.firstIndex(where: { $0.id == draftID }) else { return }
            let target = index + offset
            guard list.indices.contains(target) else { return }
            list.swapAt(index, target)
        }
    }

    func moveSections(from source: IndexSet, to destination: Int) {
        change { list in
            let moving = source.sorted().map { list[$0] }
            let before = source.filter { $0 < destination }.count
            for index in source.sorted(by: >) { list.remove(at: index) }
            list.insert(contentsOf: moving, at: destination - before)
        }
    }

    func openDraft(id: UUID) { showDraft(id) }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DocumentBlock.plainText(document.blocks), forType: .string)
        justCopied = true
        copyToken += 1
        let token = copyToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.copyToken == token { self?.justCopied = false }
        }
    }

    @MainActor
    func export(format: DraftFormat) {
        let blocks = document.blocks
        if !CompilationExporter.export(blocks, name: title, as: format) { store.announce(L("compile.exportFailed")) }
    }
}
