import SwiftUI

/// At the top of the sidebar: which project is open, with a menu to switch, create, rename and archive.
struct ProjectSwitcher: View {
    let viewModel: any IProjectsViewModel

    private enum Sheet: String, Identifiable {
        case create, rename
        var id: String { rawValue }
    }

    @State private var sheet: Sheet?
    @State private var name = ""

    var body: some View {
        Menu {
            ForEach(viewModel.projects) { project in
                Button { viewModel.select(id: project.id) } label: {
                    if project.isCurrent {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
            Divider()
            Button(L("project.new")) {
                name = ""
                sheet = .create
            }
            if let current = viewModel.current {
                Button(L("project.rename")) {
                    name = current.name
                    sheet = .rename
                }
                Button(L("project.archive")) { viewModel.archive(id: current.id) }
                    .disabled(!viewModel.canArchive)
            }
            if !viewModel.archived.isEmpty {
                Menu(L("project.archived")) {
                    ForEach(viewModel.archived) { project in
                        Button(Lf("project.restore", project.name)) { viewModel.restore(id: project.id) }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(Palette.accent)
                Text(viewModel.current?.name ?? "")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Palette.ink3)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(L("project.switcher.help"))
        .sheet(item: $sheet) { kind in form(kind) }
    }

    private func form(_ kind: Sheet) -> some View {
        let save = {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            switch kind {
            case .create: viewModel.create(name: clean)
            case .rename: if let current = viewModel.current { viewModel.rename(id: current.id, name: clean) }
            }
            sheet = nil
        }
        return VStack(alignment: .leading, spacing: 14) {
            Text(kind == .create ? L("project.new.title") : L("project.rename.title")).font(.headline)
            TextField(L("project.name.placeholder"), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button(L("reader.cancel")) { sheet = nil }.keyboardShortcut(.cancelAction)
                Button(kind == .create ? L("card.create") : L("project.save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
