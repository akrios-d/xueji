import SwiftUI
import XuejiCore

extension Stage {
    var title: String {
        switch self {
        case .toRead: return L("stage.toRead")
        case .reading: return L("stage.reading")
        case .inReview: return L("stage.inReview")
        case .done: return L("stage.done")
        }
    }

    var symbol: String {
        switch self {
        case .toRead: return "tray"
        case .reading: return "book"
        case .inReview: return "eye"
        case .done: return "checkmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .toRead: return Palette.ink3
        case .reading: return Palette.accent
        case .inReview: return Palette.neg
        case .done: return Palette.pos
        }
    }

    /// The digit key that moves a selected card here (1 for the first stage).
    var shortcutDigit: Int {
        (Stage.allCases.firstIndex(of: self) ?? 0) + 1
    }
}

extension Classification {
    var title: String {
        switch self {
        case .essential: return L("classification.essential")
        case .complementary: return L("classification.complementary")
        case .secondary: return L("classification.secondary")
        }
    }

    /// One line that says what the classification means (from the source triage key).
    var summary: String { L("classification." + rawValue + ".summary") }

    var color: Color {
        switch self {
        case .essential: return Palette.pos
        case .complementary: return Palette.accent
        case .secondary: return Palette.neg
        }
    }
}

extension ItemKind {
    var symbol: String {
        switch self {
        case .researchRequest: return "magnifyingglass"
        case .source: return "doc.text"
        case .note: return "note.text"
        case .statement: return "quote.bubble"
        case .custom: return "square.text.square"
        }
    }
}

extension KanbanFilter {
    var title: String {
        switch self {
        case .all: return L("filter.all")
        case .essential: return Classification.essential.title
        case .complementary: return Classification.complementary.title
        case .secondary: return Classification.secondary.title
        case .notes: return L("filter.notes")
        case .overdue: return L("filter.overdue")
        }
    }
}

extension KanbanSort {
    var title: String { L("sort." + rawValue) }
}

struct ClassificationPill: View {
    let classification: Classification

    var body: some View {
        Text(classification.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(classification.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(classification.color.opacity(0.14), in: Capsule())
            .help(classification.summary)
    }
}

extension ItemType {
    /// Built-in types are translated; types people create show the name they typed.
    var displayName: String {
        key.map { localizedOr("type.\($0)", name) } ?? name
    }

    func displayLabel(of field: FieldDefinition) -> String {
        key.map { localizedOr("field.\($0).\(field.key)", field.label) } ?? field.label
    }

    func displayLabel(of option: FieldOption, in field: FieldDefinition) -> String {
        key.map { localizedOr("option.\($0).\(field.key).\(option.key)", option.label) } ?? option.label
    }
}

/// Looks a key up and falls back to `fallback` when there is no translation (for fields and options that
/// people added to a built-in type).
private func localizedOr(_ key: String, _ fallback: String) -> String {
    Localization.bundle.localizedString(forKey: key, value: fallback, table: nil)
}

/// A thin progress bar that stays visible on every theme.
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.border)
                Capsule()
                    .fill(Palette.pos)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(width: 160, height: 6)
    }
}

/// A deadline chip: red when late, accent when due today, quiet otherwise.
struct DueBadgeView: View {
    let badge: DueBadge

    private var color: Color {
        switch badge.tone {
        case .overdue: return Palette.danger
        case .today: return Palette.accent
        case .soon: return Palette.ink2
        case .later: return Palette.ink3
        }
    }

    var body: some View {
        Label(badge.text, systemImage: badge.tone == .overdue ? "exclamationmark.circle.fill" : "calendar")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// A small keyboard key, used to show shortcuts.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.border))
    }
}
