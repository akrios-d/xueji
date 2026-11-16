import SwiftUI
import XuejiCore

/// Menu bar commands and their keyboard shortcuts.
struct XuejiCommands: Commands {
    let container: AppContainer
    @Environment(\.openWindow) private var openWindow

    /// Opens the References screen on one of its tabs.
    private func openReferences(_ tab: String) {
        UserDefaults.standard.set(tab, forKey: "referencesTab")
        container.shell.select(.references)
    }

    var body: some Commands {
        // Replaces "New Window": a new card is what ⌘N should do here, from any section.
        CommandGroup(replacing: .newItem) {
            Button(L("card.new")) {
                container.shell.select(.inbox)
                container.newCard.present()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(after: .help) {
            Divider()
            Button(L("menu.pdfReport")) { PDFDiagnostics.saveReport() }
        }

        CommandGroup(after: .newItem) {
            Button(L("menu.importPDF")) {
                container.shell.select(.inbox)
                container.inbox.requestImport(nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            Button(L("menu.importTriage")) {
                container.shell.select(.inbox)
                container.inbox.requestImport(.sourceTriage)
            }
            Button(L("menu.importStatements")) {
                container.shell.select(.inbox)
                container.inbox.requestImport(.statements)
            }
            Button(L("menu.importEvidenceReport")) {
                container.shell.select(.inbox)
                container.inbox.requestImport(.evidenceReport)
            }
            Button(L("menu.addPDF")) {
                container.shell.select(.inbox)
                container.inbox.requestAddPDF()
            }
            .keyboardShortcut("i", modifiers: [.command, .option, .shift])
        }

        // ⌘1…⌘9 follow the sidebar from top to bottom.
        CommandMenu(L("menu.go")) {
            Button(L("sidebar.board")) { container.shell.select(.board) }
                .keyboardShortcut("1", modifiers: .command)
            Button(L("sidebar.calendar")) { container.shell.select(.calendar) }
                .keyboardShortcut("2", modifiers: .command)
            Button(L("sidebar.inbox")) { container.shell.select(.inbox) }
                .keyboardShortcut("3", modifiers: .command)
            Button(L("sidebar.library")) { container.shell.select(.library) }
                .keyboardShortcut("4", modifiers: .command)
            Button(L("sidebar.writing")) { container.shell.select(.writing) }
                .keyboardShortcut("5", modifiers: .command)
            Button(L("sidebar.compile")) { container.shell.select(.compile) }
                .keyboardShortcut("6", modifiers: .command)
            Button(L("sidebar.references")) { container.shell.select(.references) }
                .keyboardShortcut("7", modifiers: .command)
            Button(L("sidebar.evidence")) { container.shell.select(.evidence) }
                .keyboardShortcut("8", modifiers: .command)
            Button(L("sidebar.progress")) { container.shell.select(.progress) }
                .keyboardShortcut("9", modifiers: .command)
            Divider()
            Button(L("references.tab.find")) { openReferences("find") }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button(L("references.tab.convert")) { openReferences("convert") }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button(L("references.tab.links")) { openReferences("links") }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button(L("sidebar.prompts")) { container.shell.select(.prompts) }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Divider()
            ForEach(Stage.allCases, id: \.self) { stage in
                Button(stage.title) { container.shell.select(.stage(stage)) }
            }
        }

        CommandMenu(L("sidebar.board")) {
            Button(L("undo.button")) { container.kanban.undo() }
            Button(L("redo.button")) { container.kanban.redo() }
            Divider()
            Button(L("menu.previousStage")) { container.kanban.moveSelectedToPreviousStage() }
                .keyboardShortcut("[", modifiers: .command)
            Button(L("menu.nextStage")) { container.kanban.moveSelectedToNextStage() }
                .keyboardShortcut("]", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Menu(L("theme.label")) {
                ForEach(AppTheme.allCases) { theme in
                    Button(theme.title) { container.settings.setTheme(theme) }
                }
            }
            Button(L("theme.next")) { container.settings.nextTheme() }
                .keyboardShortcut("t", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .help) {
            Button(L("menu.shortcuts")) { openWindow(id: "shortcuts") }
                .keyboardShortcut("/", modifiers: .command)
        }
    }
}
