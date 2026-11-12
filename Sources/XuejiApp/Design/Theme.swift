import AppKit
import SwiftUI

// MARK: - Themes
// The same six themes as CogNote. "Automatic" is Warm in light mode and Night in dark mode.

enum AppTheme: String, CaseIterable, Identifiable {
    case auto, warm, bw, dark, blue, navy

    static let storageKey = "appTheme"

    static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .auto
    }

    var id: String { rawValue }
    var title: String { L("theme." + rawValue) }

    /// Dark themes force a dark window; Automatic follows the Mac.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .dark, .navy: return .dark
        case .warm, .bw, .blue: return .light
        }
    }

    var next: AppTheme {
        let all = AppTheme.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    func palette(darkMode: Bool) -> ThemePalette {
        switch self {
        case .auto: return darkMode ? .dark : .warm
        case .warm: return .warm
        case .bw: return .bw
        case .dark: return .dark
        case .blue: return .blue
        case .navy: return .navy
        }
    }
}

struct ThemePalette {
    let bg: UInt32
    let surface: UInt32
    let surfaceAlt: UInt32
    let border: UInt32
    let ink: UInt32
    let ink2: UInt32
    let ink3: UInt32
    let accent: UInt32
    let accentLight: UInt32
    let onAccent: UInt32
    let danger: UInt32
    let pos: UInt32
    let neg: UInt32

    static let warm = ThemePalette(
        bg: 0xFAF9F7, surface: 0xFFFFFF, surfaceAlt: 0xF4F2EF, border: 0xE2DDD8,
        ink: 0x1C1917, ink2: 0x57534E, ink3: 0x78716C,
        accent: 0xA3561E, accentLight: 0xFDF0E8, onAccent: 0xFFFFFF, danger: 0xD96B6B,
        pos: 0x4A7C59, neg: 0x6B7FA3
    )

    static let bw = ThemePalette(
        bg: 0xF5F5F5, surface: 0xFFFFFF, surfaceAlt: 0xEBEBEB, border: 0xD0D0D0,
        ink: 0x0A0A0A, ink2: 0x333333, ink3: 0x666666,
        accent: 0x111111, accentLight: 0xEEEEEE, onAccent: 0xFFFFFF, danger: 0xCC2200,
        pos: 0x2A2A2A, neg: 0x666666
    )

    static let dark = ThemePalette(
        bg: 0x191919, surface: 0x242424, surfaceAlt: 0x2E2E2E, border: 0x383838,
        ink: 0xC8C8C8, ink2: 0x8C8C8C, ink3: 0x606060,
        accent: 0xABABAB, accentLight: 0x2A2A2A, onAccent: 0x191919, danger: 0xE07070,
        pos: 0x909090, neg: 0x686868
    )

    static let blue = ThemePalette(
        bg: 0xF0F4FD, surface: 0xFFFFFF, surfaceAlt: 0xE6EDF8, border: 0xC5D3E8,
        ink: 0x1A2540, ink2: 0x445070, ink3: 0x6476A0,
        accent: 0x1E44D4, accentLight: 0xEFF6FF, onAccent: 0xFFFFFF, danger: 0xDC3545,
        pos: 0x2E7D52, neg: 0x7C5CBF
    )

    static let navy = ThemePalette(
        bg: 0x111827, surface: 0x1A2236, surfaceAlt: 0x222D45, border: 0x2D3D5C,
        ink: 0xB8C8E8, ink2: 0x7A90B8, ink3: 0x516080,
        accent: 0x5B8DEE, accentLight: 0x1E2A44, onAccent: 0x111827, danger: 0xE07070,
        pos: 0x60A878, neg: 0x6080B8
    )
}

// MARK: - Palette
// Resolves against the selected theme each time a colour is drawn.

enum Palette {
    static let bg = themed { $0.bg }
    static let surface = themed { $0.surface }
    static let surfaceAlt = themed { $0.surfaceAlt }
    static let border = themed { $0.border }
    static let ink = themed { $0.ink }
    static let ink2 = themed { $0.ink2 }
    static let ink3 = themed { $0.ink3 }
    static let accent = themed { $0.accent }
    static let accentLight = themed { $0.accentLight }
    /// Text and icons on an accent-filled button.
    static let onAccent = themed { $0.onAccent }
    static let danger = themed { $0.danger }
    static let pos = themed { $0.pos }
    static let neg = themed { $0.neg }

    private static func themed(_ pick: @escaping (ThemePalette) -> UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: pick(AppTheme.current.palette(darkMode: isDark)))
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}
