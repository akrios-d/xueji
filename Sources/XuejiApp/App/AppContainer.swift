import Foundation
import XuejiCore

/// Composition root: builds the model once and hands each screen its view model.
/// View models are created here, never inside a view, so their state survives re-renders.
final class AppContainer {
    let shell: ShellViewModel
    let kanban: KanbanViewModel
    let cardPanel: CardPanelViewModel
    let newCard: NewCardViewModel
    let calendar: CalendarViewModel
    let inbox: InboxViewModel
    let writing: WritingViewModel
    let compile: CompileViewModel
    let progress: ProgressViewModel
    let converter = ConverterViewModel()
    let finder: FinderViewModel
    let links = LinksViewModel()
    let prompts = PromptsViewModel()
    let evidence: EvidenceViewModel
    let projects: ProjectsViewModel
    let library: LibraryViewModel
    let reader: ReaderViewModel
    let settings: SettingsViewModel

    init() {
        let store: AppStore
        switch Persistence.load() {
        case .loaded(var snapshot):
            snapshot.workspace.mergeBuiltInTypes()
            store = AppStore(
                workspace: snapshot.workspace, meID: snapshot.meID, trackID: snapshot.trackID,
                drafts: snapshot.drafts.map { draft in
                    // Drafts saved before there were projects belong to the first one.
                    var draft = draft
                    if draft.trackID == nil { draft.trackID = snapshot.trackID }
                    return draft
                },
                readingVersions: Dictionary(grouping: snapshot.versions, by: \.itemID),
                compilations: snapshot.compilations ?? snapshot.compilation.map { [snapshot.trackID: $0] } ?? [:],
                triageSets: snapshot.triageSets ?? snapshot.triages?.mapValues { [$0] } ?? [:]
            )
        case .fresh:
            let start = StartingWorkspace.make()
            store = AppStore(workspace: start.workspace, meID: start.meID, trackID: start.trackID)
        case .unreadable(let moved):
            let start = StartingWorkspace.make()
            store = AppStore(
                workspace: start.workspace, meID: start.meID, trackID: start.trackID,
                startupMessage: Lf("persistence.unreadable", moved.lastPathComponent)
            )
        }
        shell = ShellViewModel(store: store)
        kanban = KanbanViewModel(store: store)
        cardPanel = CardPanelViewModel(store: store)
        newCard = NewCardViewModel(store: store)
        calendar = CalendarViewModel(store: store)
        inbox = InboxViewModel(store: store)
        writing = WritingViewModel(store: store)
        compile = CompileViewModel(store: store)
        progress = ProgressViewModel(store: store)
        finder = FinderViewModel(store: store)
        evidence = EvidenceViewModel(store: store)
        projects = ProjectsViewModel(store: store)
        library = LibraryViewModel(store: store)
        let colors = ColorLibrary()
        reader = ReaderViewModel(store: store, colors: colors)
        store.markColorsFound = { [colors] hexes in
            for hex in hexes where colors.color(forHex: hex) == nil {
                var name = HighlightImporter.colorName(hex: hex)
                if colors.colors.contains(where: { $0.displayName == name }) { name += " #" + hex }
                colors.add(name: name, hex: hex)
            }
        }
        settings = SettingsViewModel()
        inbox.showLibrary = { [shell] in shell.select(.library) }
        inbox.showEvidence = { [shell] in shell.select(.evidence) }
        let readInApp: (UUID) -> Void = { [shell, reader] id in
            reader.open(itemID: id)
            shell.select(.reader)
        }
        library.readInApp = readInApp
        kanban.readInApp = readInApp
        evidence.readInApp = readInApp
        evidence.readAt = { [shell, reader] id, page, term in
            reader.open(itemID: id, page: page, search: term.isEmpty ? nil : term)
            shell.select(.reader)
        }
        cardPanel.readInApp = readInApp
        reader.onClose = { [shell] in shell.closeReader() }
        projects.didSwitch = { [shell, writing, evidence] in
            evidence.refresh()
            // A PDF open in the reader belongs to the project just left.
            if shell.selectedSection == .reader { shell.select(.library) }
            writing.select(draftID: nil)
        }
        progress.showDraft = { [shell, writing] id in
            writing.select(draftID: id)
            shell.select(.writing)
        }
        compile.showDraft = { [shell, writing] id in
            writing.select(draftID: id)
            shell.select(.writing)
        }
        writing.openSource = { [shell, reader] id, page, phrase in
            reader.open(itemID: id, page: page, search: phrase)
            shell.select(.reader)
        }
        writing.openCard = { [shell, kanban, reader, store] id in
            if let item = store.workspace.items[id], item.kind == .source, item.url?.isFileURL == true {
                reader.open(itemID: id)
                shell.select(.reader)
            } else {
                store.focus(id)
                kanban.setPanelShown(true)
                shell.select(.board)
            }
        }
    }
}
