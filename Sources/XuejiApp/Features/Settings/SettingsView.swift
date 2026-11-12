import SwiftUI

struct SettingsView: View {
    let viewModel: any ISettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("settings.appearance"))
                .font(.heading(.title2).weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(L("settings.appearance.hint"))
                .font(.callout)
                .foregroundStyle(Palette.ink2)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 14) {
                ForEach(viewModel.themes) { theme in
                    ThemeSwatch(theme: theme, isSelected: theme == viewModel.theme) {
                        viewModel.setTheme(theme)
                    }
                }
            }
            .padding(.top, 4)
            Divider().padding(.vertical, 6)
            Text(L("settings.language"))
                .font(.heading(.title2).weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(L("settings.language.hint"))
                .font(.callout)
                .foregroundStyle(Palette.ink2)
            Picker(L("settings.language"), selection: Binding(
                get: { viewModel.language }, set: { viewModel.setLanguage($0) }
            )) {
                ForEach(viewModel.languages) { language in Text(language.title).tag(language) }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
        }
        .padding(24)
        .frame(width: 460)
        .background(Palette.bg)
        .preferredColorScheme(viewModel.theme.colorScheme)
        .id("\(viewModel.theme.rawValue)-\(viewModel.language.rawValue)")
        .environment(\.locale, Localization.locale)
    }
}

private struct ThemeSwatch: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = theme.palette(darkMode: colorScheme == .dark)
        return Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Color(hex: colors.bg))
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(Color(hex: colors.accent)).frame(width: 34, height: 6)
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Color(hex: colors.surface))
                            .frame(height: 22)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .strokeBorder(Color(hex: colors.border))
                            )
                    }
                    .padding(10)
                }
                .frame(height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 2 : 1)
                )
                Text(theme.title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Palette.ink)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
