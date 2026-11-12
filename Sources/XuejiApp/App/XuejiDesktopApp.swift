import AppKit
import SwiftUI

@main
struct XuejiDesktopApp: App {
    @State private var container = AppContainer()

    init() {
        // Needed so a SwiftPM executable gets a window, a Dock icon and keyboard focus.
        NSApplication.shared.setActivationPolicy(.regular)
        // A SwiftPM executable is not an app bundle, so the Dock would show a blank icon. Set it from the
        // bundled artwork (the real app icon comes with the Xcode app project).
        #if SWIFT_PACKAGE
        if let url = AppBundle.resources.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
        #endif
    }

    var body: some Scene {
        // Window titles and menus are built from strings; reading the language here rebuilds them when it changes.
        let _ = container.settings.language
        WindowGroup(L("app.name")) {
            RootView(container: container)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1120, height: 720)
        .windowToolbarStyle(.unified)
        .commands { XuejiCommands(container: container) }

        Window(L("shortcuts.title"), id: "shortcuts") {
            ShortcutsView(settings: container.settings)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(viewModel: container.settings)
        }
    }
}
