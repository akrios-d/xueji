import SwiftUI
import XuejiCore

struct RootView: View {
    let container: AppContainer

    private var shell: any IShellViewModel { container.shell }
    private var settings: any ISettingsViewModel { container.settings }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .tint(Palette.accent)
        .overlay(alignment: .bottom) { errorBanner }
        .animation(.easeInOut(duration: 0.2), value: shell.errorMessage)
        .preferredColorScheme(settings.theme.colorScheme)
        // Palette colours read the theme when they resolve, so rebuild the tree when it changes.
        .id("\(settings.theme.rawValue)-\(settings.language.rawValue)")
        .environment(\.locale, Localization.locale)
    }

    // MARK: Sidebar

    private var sectionBinding: Binding<AppSection?> {
        Binding(
            get: { shell.selectedSection == .reader ? .library : shell.selectedSection },
            set: { if let section = $0 { shell.select(section) } }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { settings.language }, set: { settings.setLanguage($0) })
    }

    private var themeBinding: Binding<AppTheme> {
        Binding(get: { settings.theme }, set: { settings.setTheme($0) })
    }

    private var sidebar: some View {
        List(selection: sectionBinding) {
            Section(L("sidebar.workspace")) {
                Label(L("sidebar.board"), systemImage: "rectangle.split.3x1")
                    .tag(AppSection.board)
                Label(L("sidebar.calendar"), systemImage: "calendar")
                    .tag(AppSection.calendar)
                // The badge goes before the tag: a modifier applied after `.tag` hides the tag from the
                // List, and the row then can't be selected.
                Label(L("sidebar.inbox"), systemImage: "tray")
                    .badge(shell.pendingApprovalCount)
                    .tag(AppSection.inbox)
                Label(L("sidebar.library"), systemImage: "books.vertical")
                    .tag(AppSection.library)
                Label(L("sidebar.writing"), systemImage: "square.and.pencil")
                    .tag(AppSection.writing)
                Label(L("sidebar.compile"), systemImage: "text.book.closed")
                    .tag(AppSection.compile)
                Label(L("sidebar.triage"), systemImage: "quote.bubble")
                    .tag(AppSection.triage)
            }
            Section(L("sidebar.stages")) {
                ForEach(Stage.allCases, id: \.self) { stage in
                    Label(stage.title, systemImage: stage.symbol)
                        .badge(shell.cardCount(in: stage))
                        .tag(AppSection.stage(stage))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        .safeAreaInset(edge: .top, spacing: 0) {
            ProjectSwitcher(viewModel: container.projects)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Menu {
                    Picker(L("theme.label"), selection: themeBinding) {
                        ForEach(settings.themes) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(L("theme.label"), systemImage: "paintpalette")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Menu {
                    Picker(L("settings.language"), selection: languageBinding) {
                        ForEach(settings.languages) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(L("settings.language"), systemImage: "globe")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch shell.selectedSection {
        case .board: KanbanView(viewModel: container.kanban, panel: container.cardPanel, stage: nil)
        case .stage(let stage): KanbanView(viewModel: container.kanban, panel: container.cardPanel, stage: stage)
        case .writing: WritingView(viewModel: container.writing)
        case .compile: CompileView(viewModel: container.compile)
        case .triage: TriageView(viewModel: container.triage)
        case .library: LibraryView(viewModel: container.library)
        case .reader: ReaderView(viewModel: container.reader)
        case .calendar: CalendarView(viewModel: container.calendar)
        case .inbox: InboxView(viewModel: container.inbox, newCard: container.newCard)
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = shell.errorMessage {
            Text(message)
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.border))
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .transition(.opacity)
                .onTapGesture { shell.dismissError() }
                .task(id: message) {
                    // A long message (a diagnosis) stays long enough to read and copy.
                    try? await Task.sleep(for: .seconds(max(4, message.count / 10)))
                    shell.dismissError()
                }
        }
    }
}
