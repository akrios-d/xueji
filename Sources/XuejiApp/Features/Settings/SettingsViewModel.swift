import Foundation
import Observation

@Observable
final class SettingsViewModel: ISettingsView, ISettingsController {
    private let defaults: UserDefaults
    private(set) var theme: AppTheme
    private(set) var language: AppLanguage

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = AppTheme.current
        self.language = AppLanguage.current
    }

    // MARK: ISettingsView

    var themes: [AppTheme] { AppTheme.allCases }
    var languages: [AppLanguage] { AppLanguage.allCases }

    // MARK: ISettingsController

    func setTheme(_ theme: AppTheme) {
        // Write first: palette colours read the stored value when they resolve.
        defaults.set(theme.rawValue, forKey: AppTheme.storageKey)
        self.theme = theme
    }

    func setLanguage(_ language: AppLanguage) {
        // Write first, then switch the strings; the screens rebuild when `language` changes.
        defaults.set(language.rawValue, forKey: AppLanguage.storageKey)
        Localization.apply(language)
        self.language = language
    }

    func nextTheme() {
        setTheme(theme.next)
    }
}
