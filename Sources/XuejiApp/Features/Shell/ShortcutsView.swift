import SwiftUI

/// The keyboard shortcut cheat sheet (⌘/). Static reference content, so it has no view model of its own.
struct ShortcutsView: View {
    let settings: any ISettingsView

    private struct Row {
        let keys: [String]
        let label: String
    }

    private struct Group {
        let title: String
        let rows: [Row]
    }

    private var groups: [Group] {
        [
            Group(title: L("shortcuts.navigate"), rows: [
                Row(keys: ["⌘1", "…", "⌘9"], label: L("shortcuts.sections")),
                Row(keys: ["⌥⌘1", "⌥⌘2", "⌥⌘3"], label: L("shortcuts.referenceTabs")),
                Row(keys: ["⌥⌘P"], label: L("sidebar.prompts")),
                Row(keys: ["⌘F"], label: L("shortcuts.search")),
                Row(keys: ["⌘N"], label: L("card.new")),
                Row(keys: ["⇧⌘I"], label: L("menu.importPDF")),
                Row(keys: ["⌥⇧⌘I"], label: L("menu.addPDF")),
            ]),
            Group(title: L("shortcuts.board"), rows: [
                Row(keys: ["←", "↑", "↓", "→"], label: L("shortcuts.select")),
                Row(keys: ["1", "2", "3", "4"], label: L("shortcuts.moveToStage")),
                Row(keys: ["⌘[", "⌘]"], label: L("shortcuts.moveStage")),
                Row(keys: ["↩"], label: L("shortcuts.openPanel")),
                Row(keys: ["⌘I"], label: L("shortcuts.togglePanel")),
                Row(keys: ["O"], label: L("shortcuts.openLink")),
                Row(keys: ["esc"], label: L("shortcuts.clear")),
                Row(keys: ["T", "M", "W", "X"], label: L("shortcuts.dueDate")),
                Row(keys: ["⌫"], label: L("board.discard")),
                Row(keys: ["⌘Z", "⇧⌘Z"], label: L("shortcuts.undoRedo")),
            ]),
            Group(title: L("shortcuts.reader"), rows: [
                Row(keys: ["⇧⌘H"], label: L("reader.highlight")),
                Row(keys: ["⌥⌘L"], label: L("reader.marks.toggle")),
            ]),
            Group(title: L("shortcuts.calendar"), rows: [
                Row(keys: ["←", "→", "↑", "↓"], label: L("shortcuts.day")),
                Row(keys: ["T"], label: L("shortcuts.today")),
                Row(keys: ["M"], label: L("shortcuts.newMilestone")),
                Row(keys: ["⇞", "⇟"], label: L("shortcuts.month")),
            ]),
            Group(title: L("shortcuts.inbox"), rows: [
                Row(keys: ["↑", "↓"], label: L("shortcuts.select")),
                Row(keys: ["A", "↩"], label: L("inbox.approve")),
                Row(keys: ["D", "⌫"], label: L("inbox.reject")),
            ]),
            Group(title: L("shortcuts.app"), rows: [
                Row(keys: ["⌥⌘T"], label: L("theme.next")),
                Row(keys: ["⌘,"], label: L("shortcuts.settings")),
                Row(keys: ["⌘/"], label: L("shortcuts.list")),
            ]),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(Palette.ink3)
                        VStack(spacing: 0) {
                            ForEach(group.rows, id: \.label) { row in
                                HStack {
                                    Text(row.label).foregroundStyle(Palette.ink)
                                    Spacer()
                                    HStack(spacing: 4) {
                                        ForEach(row.keys, id: \.self) { KeyCap(label: $0) }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                if row.label != group.rows.last?.label { Divider() }
                            }
                        }
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 440, height: 700)
        .background(Palette.bg)
        .preferredColorScheme(settings.theme.colorScheme)
        .id(settings.theme)
    }
}
