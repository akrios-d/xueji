import SwiftUI
import UniformTypeIdentifiers
import XuejiCore

/// Every source the student keeps: web links and PDFs added from the Mac. Open one to read it.
struct LibraryView: View {
    let viewModel: any ILibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            noticeBanner
            if viewModel.totalCount == 0 {
                emptyState
            } else {
                Picker("", selection: Binding(get: { viewModel.filter }, set: { viewModel.setFilter($0) })) {
                    ForEach(LibraryFilter.allCases) { Text(L("library.filter." + $0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .padding(.top, 16)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.sources) { item in row(item) }
                        if viewModel.sources.isEmpty {
                            Text(L("library.noMatches")).foregroundStyle(Palette.ink2).padding(.vertical, 40)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Palette.bg)
        .navigationTitle(L("library.title"))
        .navigationSubtitle(Lf("library.count", viewModel.totalCount))
        .searchable(text: Binding(get: { viewModel.searchText }, set: { viewModel.setSearchText($0) }),
                    placement: .toolbar, prompt: Text(L("library.search")))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { viewModel.requestAdd() } label: {
                    Label(L("inbox.addPDF"), systemImage: "plus")
                }
                .help(L("inbox.addPDF.help"))
            }
        }
        .fileImporter(
            isPresented: Binding(get: { viewModel.isChoosingFile }, set: { viewModel.setChoosingFile($0) }),
            allowedContentTypes: [.pdf]
        ) { result in
            if case .success(let url) = result { viewModel.addPDF(at: url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            pdfs.forEach { viewModel.addPDF(at: $0) }
            return !pdfs.isEmpty
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let message = viewModel.notice {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(Palette.accent)
                Text(message).font(.callout).foregroundStyle(Palette.ink)
                Spacer()
                Button { viewModel.dismissNotice() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink3)
            }
            .padding(12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
    }

    private func row(_ item: Item) -> some View {
        let isSelected = item.id == viewModel.selectedItemID
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: viewModel.isFile(item) ? "doc.richtext" : "link")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 28, height: 28)
                .background(Palette.accentLight, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.heading(.headline)).foregroundStyle(Palette.ink)
                Text(viewModel.subtitle(of: item)).font(.caption).foregroundStyle(Palette.ink3).lineLimit(2)
                if let classification = item.classification {
                    ClassificationPill(classification: classification)
                }
            }
            Spacer()
            if item.url != nil {
                Button(viewModel.isFile(item) ? L("library.read") : L("library.openLink")) {
                    viewModel.read(itemID: item.id)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { viewModel.select(itemID: item.id) }
        .onTapGesture(count: 2) { viewModel.read(itemID: item.id) }
        .contextMenu {
            Button(viewModel.isFile(item) ? L("library.read") : L("library.openLink")) { viewModel.read(itemID: item.id) }
            if viewModel.isFile(item) {
                Button(L("library.openPreview")) { viewModel.open(itemID: item.id) }
            }
            if !viewModel.otherProjects.isEmpty {
                Menu(L("project.copyTo")) {
                    ForEach(viewModel.otherProjects) { project in
                        Button(project.name) { viewModel.copy(itemID: item.id, toProject: project.id) }
                    }
                }
            }
            Divider()
            Button(L("library.remove"), role: .destructive) { viewModel.remove(itemID: item.id) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.ink3)
            Text(L("library.empty.title"))
                .font(.heading(.title2).weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(L("library.empty.description"))
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button(L("inbox.addPDF")) { viewModel.requestAdd() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
