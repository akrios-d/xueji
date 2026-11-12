import Foundation

/// What the settings screen (and every themed window) may read.
protocol ISettingsView {
    var theme: AppTheme { get }
    var themes: [AppTheme] { get }
    var language: AppLanguage { get }
    var languages: [AppLanguage] { get }
}

/// What the settings screen may trigger.
protocol ISettingsController {
    func setTheme(_ theme: AppTheme)
    func nextTheme()
    func setLanguage(_ language: AppLanguage)
}

typealias ISettingsViewModel = ISettingsView & ISettingsController
