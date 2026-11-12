# CLAUDE.md — Xueji coding guidelines

Native Mac app (SwiftUI) for PhD and master's students. Read `README.md` and `docs/xueji-specification.md` first.

## Stack

- Swift (tools 5.9), SwiftUI and Observation (`@Observable`), macOS 14+.
- No third-party dependencies yet (GRDB is planned for SQLite).
- Tests: XCTest (`swift test`).

## Language

- All code, identifiers, comments, commit messages and documentation are in English.
- User-facing text goes through `L()` / `Lf()`. Add every new key to both `en.lproj` and `zh-Hans.lproj` in the same change.

## Architecture: Contracted MVVM (always)

1. **Model:** `XuejiCore` holds the domain types and every business rule (no UI, no I/O). `Models/AppStore` applies changes through the core. Business rules never live in a view or a view model.
2. **Contracts first:** each feature declares `IXxxView` (what the screen reads) and `IXxxController` (what it triggers) in `XxxContracts.swift` before any implementation.
3. **ViewModel:** an `@Observable` class that implements both contracts. It owns UI state and receives the store through `init`; it never creates it.
4. **View:** depends only on the contracts (`any IXxxViewModel`). No business logic, no direct store access, no view model creation.
5. **Composition root:** `App/AppContainer` creates the store and every view model once.
6. **One folder per feature:** `Features/<Name>/` with `XxxContracts.swift`, `XxxViewModel.swift` and `XxxView.swift`.
7. A new screen follows these steps in order: contracts, view model, view, localization keys, tests for any new rule.

## Working rules

- **Think before coding:** state assumptions, surface trade-offs, ask when unclear.
- **Simplicity first:** the minimum code that solves the problem, with no speculative abstractions.
- **Surgical changes:** touch only what the request needs, and match the existing style.
- **Goal-driven:** turn each task into checks you can verify (tests first for new rules).

## Design

- Load resources and strings through `AppBundle.resources` (via `L()`), never `Bundle.module` directly: the Xcode app target has no `Bundle.module`.
- Use `Palette`, `Radius` and `Font.heading` from `Design/`. Do not hard-code colours or radii: colours come from the selected theme (`Design/Theme.swift`, six themes shared with CogNote).
- Every new action gets a keyboard shortcut when it makes sense, and an entry in `ShortcutsView`.
- Shadows only on hover and drag. Motion around 200 ms. Native controls first.
- Tone of text: short, calm, no technical jargon, no emojis.

## Security

- Validate all external input at the boundary (the API, when it exists).
- No secrets in code or logs. Tokens go in the Keychain.
- Least privilege: agents never approve their own work.
