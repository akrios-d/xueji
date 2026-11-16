import SwiftUI

// MARK: - Resources
// SwiftPM builds keep resources in `Bundle.module`; the Xcode app target keeps them in the main bundle.
// Always go through `AppBundle.resources`, never `Bundle.module` directly.

enum AppBundle {
    static let resources: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }()
}

// MARK: - Localization
// English is the base language. Keys live in Resources/<language>.lproj/Localizable.strings.

func L(_ key: String) -> String {
    Localization.bundle.localizedString(forKey: key, value: nil, table: nil)
}

func Lf(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}

// MARK: - Radii and type

/// Spacing scale shared by the screens, so paddings stay consistent.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 14
    static let lg: CGFloat = 24
}

enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 16
}

extension Font {
    /// Title of a block inside a screen.
    static var sectionTitle: Font { heading(.title3).weight(.semibold) }
    /// Title of a screen or a card.
    static var screenTitle: Font { heading(.largeTitle).weight(.bold) }

    /// Serif for headings and names, system sans for everything else (same rule as the web app).
    static func heading(_ style: Font.TextStyle = .headline) -> Font {
        .system(style, design: .serif)
    }
}
