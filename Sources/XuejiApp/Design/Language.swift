import Foundation

/// The language of the app's own text. "System" follows macOS; the others override it inside the app.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, chinese

    static let storageKey = "appLanguage"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    var id: String { rawValue }

    /// The name of the folder with its strings (nil for the system language).
    var code: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .chinese: return "zh-Hans"
        }
    }

    /// Each language is written in itself, so it can be found whatever language the app is in now.
    var title: String {
        switch self {
        case .system: return L("language.system")
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}

/// Which strings and which regional formats (dates, months) the app uses right now.
enum Localization {
    private(set) static var bundle: Bundle = makeBundle(AppLanguage.current)
    private(set) static var locale: Locale = makeLocale(AppLanguage.current)

    static func apply(_ language: AppLanguage) {
        bundle = makeBundle(language)
        locale = makeLocale(language)
    }

    private static func makeBundle(_ language: AppLanguage) -> Bundle {
        guard let code = language.code,
              let path = AppBundle.resources.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return AppBundle.resources }
        return bundle
    }

    private static func makeLocale(_ language: AppLanguage) -> Locale {
        language.code.map { Locale(identifier: $0) } ?? .current
    }
}
