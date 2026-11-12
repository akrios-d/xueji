import AppKit
import Foundation
import Observation

/// A colour for highlights and underlines. The student's own colours are stored by their hex value, which is
/// also what is written into the PDF's marks.
struct MarkColor: Hashable, Codable, Identifiable {
    /// "RRGGBB", upper case, sRGB.
    let hex: String
    var name: String
    /// Set for the colours Xueji starts with: their name follows the language of the app.
    var key: String?

    var id: String { hex }
    var displayName: String { key.map { L($0) } ?? name }
    var nsColor: NSColor { NSColor(hex: hex) ?? .systemYellow }
}

extension NSColor {
    convenience init?(hex: String) {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// "RRGGBB", or nil for a colour that cannot be expressed in sRGB.
    var hexString: String? {
        guard let color = usingColorSpace(.sRGB) else { return nil }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}

/// The student's palette of highlight colours: four to start with, then any they add. Kept in the user defaults
/// (a preference, like the theme).
@Observable
final class ColorLibrary {
    private(set) var colors: [MarkColor]
    private let defaults: UserDefaults
    private static let storageKey = "markColors"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([MarkColor].self, from: data), !saved.isEmpty {
            colors = saved
        } else {
            colors = Self.builtIn
        }
    }

    static let builtIn: [MarkColor] = [
        MarkColor(hex: "FFD60A", name: "Yellow", key: "color.yellow"),
        MarkColor(hex: "30D158", name: "Green", key: "color.green"),
        MarkColor(hex: "0A84FF", name: "Blue", key: "color.blue"),
        MarkColor(hex: "FF375F", name: "Pink", key: "color.pink"),
    ]

    /// Names used by marks made before colours were stored as hex values.
    static let legacyHex: [String: String] = [
        "yellow": "FFD60A", "green": "30D158", "blue": "0A84FF", "pink": "FF375F",
    ]

    func color(forHex hex: String) -> MarkColor? { colors.first { $0.hex == hex } }

    /// Adds a colour (or returns the one with the same value that is already there).
    @discardableResult
    func add(name: String, hex: String) -> MarkColor {
        let value = hex.uppercased()
        if let existing = color(forHex: value) { return existing }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = MarkColor(hex: value, name: clean.isEmpty ? "#" + value : clean, key: nil)
        colors.append(color)
        save()
        return color
    }

    func rename(hex: String, to name: String) {
        guard let index = colors.firstIndex(where: { $0.hex == hex }) else { return }
        colors[index].name = name
        colors[index].key = nil
        save()
    }

    /// The last colour cannot be removed: there is always one to mark with.
    func remove(hex: String) {
        guard colors.count > 1 else { return }
        colors.removeAll { $0.hex == hex }
        save()
    }

    func reset() {
        colors = Self.builtIn
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(colors) { defaults.set(data, forKey: Self.storageKey) }
    }
}
