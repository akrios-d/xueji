import SwiftUI
import XuejiCore

/// Looks a work up online (Crossref and Open Library) and prints it in the chosen style.
struct FinderView: View {
    let viewModel: any IFinderViewModel
    @State private var showingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.isOnline {
                Label(L("network.offline.finder"), systemImage: "wifi.slash")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                TextField(L("finder.placeholder"), text: Binding(get: { viewModel.query }, set: { viewModel.setQuery($0) }))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.search() }
                    .disabled(!viewModel.isOnline)
                Button(L("finder.search")) { viewModel.search() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.isOnline || viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSearching)
            }
            HStack {
                Picker(L("converter.target"), selection: Binding(get: { viewModel.style }, set: { viewModel.setStyle($0) })) {
                    ForEach(CitationStyle.allCases) { style in Text(L("compile.style." + style.rawValue)).tag(style) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                if viewModel.isSearching { ProgressView().controlSize(.small) }
                Spacer()
                Button { showingInfo.toggle() } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless)
                    .help(L("finder.info.title"))
                    .popover(isPresented: $showingInfo, arrowEdge: .bottom) { info }
            }
            Text(L("finder.hint")).font(.caption).foregroundStyle(.secondary)

            if viewModel.results.isEmpty {
                Spacer()
                if viewModel.hasSearched && !viewModel.isSearching {
                    ContentUnavailableView(L("finder.none"), systemImage: "magnifyingglass")
                } else if !viewModel.isSearching {
                    ContentUnavailableView(L("finder.empty"), systemImage: "text.magnifyingglass")
                }
                Spacer()
            } else {
                List(viewModel.results) { result in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.formatted(result))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(result.source).font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 6) {
                            Button { viewModel.copy(result) } label: { Image(systemName: "doc.on.doc") }
                                .help(L("converter.copy"))
                            Button { viewModel.addToLibrary(result) } label: { Image(systemName: "plus.square.on.square") }
                                .help(L("finder.add"))
                                .disabled(result.url.isEmpty)
                            Button { viewModel.openLink(result) } label: { Image(systemName: "arrow.up.right.square") }
                                .help(L("finder.open"))
                                .disabled(result.url.isEmpty)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
    }

    /// What the finder does and what it cannot do.
    private var info: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("finder.info.title")).font(.headline)
            infoBlock("magnifyingglass", L("finder.info.search"))
            infoBlock("text.quote", L("finder.info.result"))
            infoBlock("plus.square.on.square", L("finder.info.library"))
            infoBlock("exclamationmark.triangle", L("finder.info.limits"))
        }
        .padding(16)
        .frame(width: 340)
    }

    private func infoBlock(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}
