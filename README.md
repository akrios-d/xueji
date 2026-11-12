# Xueji 学记

Native Mac app (SwiftUI) for PhD and master's students. It organizes the daily work of research (readings, sources, chapters and notes) in tracks, with AI agents and people, such as a supervisor, helping along. Everything is stored on the device.

The name 学记 (Xuéjì) means "record of learning". It is also the title of a classical Chinese text on education.

- **Requires:** Xcode 16 or newer, macOS 14+.
- **Languages:** English (base) and Simplified Chinese. The app follows the Mac's language, and is called 学记 in Chinese.
- **Strings:** `Sources/XuejiApp/Resources/<language>.lproj/Localizable.strings`, same dot-separated keys in every language.
- **Status:** the rules engine and its tests are done, including deadlines and milestones. The app runs on sample data held in memory, with no persistence and no API yet. Notes written in place, PDFs with markings and a suggested reading order are planned.

## Running it

1. Open `Package.swift` in Xcode.
2. In the scheme picker (top bar), choose **Xueji** and **My Mac**, then press Run.
3. Press ⌘U to run the tests.

To try Chinese: **Product → Scheme → Edit Scheme → Run → Options → App Language → Chinese, Simplified**.

From the terminal: `swift run Xueji` and `swift test`.

## Architecture

Contracted MVVM. The full rules are in `CLAUDE.md`; the short version:

- **Model:** `XuejiCore` (domain and rules, no UI) and `AppStore` (applies changes through the core).
- **Contracts:** every screen declares what it reads (`IXxxView`) and what it triggers (`IXxxController`) first.
- **ViewModel:** implements both contracts and receives the store through `init`.
- **View:** depends only on the contracts and holds no logic.
- **Composition root:** `AppContainer` builds everything once.

## Structure

| Folder | What it holds |
|---|---|
| `Sources/XuejiCore/` | Models and every business rule (approval, leases, review rounds). No UI, no I/O |
| `Sources/XuejiApp/App/` | App entry point and the composition root (`AppContainer`) |
| `Sources/XuejiApp/Models/` | `AppStore` and the sample data |
| `Sources/XuejiApp/Features/<Name>/` | One folder per screen: contracts, view model and view (Shell, Kanban, Calendar, Inbox, Settings) |
| `Sources/XuejiApp/Design/` | `L()` / `Lf()` for text, palette, radii, type, shared components |
| `Sources/XuejiApp/Resources/` | Localization files |
| `Tests/XuejiCoreTests/` | Tests for the rules |
| `Icon/` | App icon assets |
| `docs/` | Technical specification and the backlog (`backlog.md`) |

## Themes and keyboard

Six themes (Automatic, Warm, B&W, Night, Blue, Navy), chosen in Settings (⌘,), the sidebar or the View menu; ⌥⌘T cycles them. The board is keyboard-first: arrows select, 1–4 move a card to a stage, ⌘[ ⌘] step through stages, ⌘F searches. Press ⌘/ in the app for the full list.

## Design

Same system as the web app and CogNote: warm off-white background, terracotta accent, serif headings and system sans for everything else. Shadows appear only on hover and drag, and motion stays around 200 ms. Native pieces (sidebar, toolbar, SF Symbols, materials) come from the system.

## Xcode project

The app also builds as a real macOS app (icon in Finder and the Dock, bundle identifier, permissions). The project is generated from `project.yml`:

1. `brew install xcodegen`
2. `xcodegen generate` (in the project folder)
3. Open `Xueji.xcodeproj`, select the **Xueji** scheme and **My Mac**.
4. Under Signing & Capabilities choose your team, and set your own bundle identifier in `project.yml` (`dev.xueji` is a placeholder).

Do not edit or commit the generated project; change `project.yml` and generate again. `swift test` keeps working from the terminal.
