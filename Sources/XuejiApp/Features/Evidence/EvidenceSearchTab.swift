import SwiftUI
import XuejiCore

/// Free search over the documents the student picks: words or phrases between quotes, with the page of every place.
struct EvidenceSearchTab: View {
    let viewModel: any IEvidenceSearchViewModel
    let evidence: any IEvidenceViewModel
    let onQuote: (EvidenceQuote) -> Void
    /// Checked places are hidden so what is left is what still has to be read (shared with the Documents tab).
    @AppStorage("evidenceShowChecked") private var showChecked = false

    var body: some View {
        HStack(spacing: 0) {
            documentColumn.frame(width: 300)
            Divider()
            resultColumn
        }
        .task { viewModel.refresh() }
    }

    // MARK: Documents

    private var documentColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("search.documents")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2)
                Spacer()
                Button(L("search.all")) { viewModel.setAll(true) }.buttonStyle(.borderless).font(.caption)
                Button(L("search.none")) { viewModel.setAll(false) }.buttonStyle(.borderless).font(.caption)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if viewModel.documents.isEmpty {
                Text(L("evidence.noSources")).font(.callout).foregroundStyle(Palette.ink3)
                    .padding(14)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.documents) { document in
                            Toggle(isOn: Binding(
                                get: { document.isOn },
                                set: { viewModel.setOn($0, id: document.id) }
                            )) {
                                Text(document.title).font(.callout).lineLimit(2)
                            }
                            .toggleStyle(.checkbox)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }

    // MARK: Results

    private var resultColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.ink3)
                TextField(L("search.placeholder"), text: Binding(
                    get: { viewModel.query },
                    set: { viewModel.setQuery($0) }
                ))
                .textFieldStyle(.plain)
                .onSubmit { viewModel.search() }
                Button(L("search.go")) { viewModel.search() }
                    .disabled(PassageSearch.terms(viewModel.query).isEmpty)
            }
            Text(L("search.hint")).font(.caption).foregroundStyle(Palette.ink3)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        let chosen = viewModel.documents.filter(\.isOn)
        if viewModel.documents.isEmpty {
            Spacer()
        } else if chosen.isEmpty {
            message(L("search.noneSelected"))
        } else if viewModel.isSearching && viewModel.hits.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(Lf("search.progress", viewModel.progress.read, viewModel.progress.total))
                    .font(.callout).foregroundStyle(Palette.ink3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.searched && viewModel.hits.isEmpty {
            message(L("search.nothing"))
        } else if viewModel.hits.isEmpty {
            Spacer()
        } else {
            results(chosen)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).foregroundStyle(Palette.ink3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func results(_ chosen: [SearchDocument]) -> some View {
        let hits = viewModel.hits
        let checkedCount = hits.filter { isChecked($0) }.count
        let shown = showChecked ? hits : hits.filter { !isChecked($0) }
        let withHits = chosen.filter { document in shown.contains { $0.sourceID == document.id } }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: []) {
                if checkedCount > 0 {
                    HStack {
                        Spacer()
                        Button {
                            showChecked.toggle()
                        } label: {
                            Text(showChecked ? L("evidence.occurrences.hideChecked") : Lf("evidence.occurrences.showChecked", checkedCount))
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if shown.isEmpty, !viewModel.isSearching {
                    Text(L("search.allChecked")).font(.caption).foregroundStyle(Palette.ink3)
                }
                ForEach(withHits) { document in
                    let own = shown.filter { $0.sourceID == document.id }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(document.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(Lf("search.count", own.count)).font(.caption).foregroundStyle(Palette.ink3)
                        }
                        ForEach(own) { hit in
                            Divider()
                            row(hit)
                        }
                    }
                }
                if viewModel.isSearching {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(Lf("search.progress", viewModel.progress.read, viewModel.progress.total))
                            .font(.caption).foregroundStyle(Palette.ink3)
                    }
                }
                if hits.count >= viewModel.hitLimit {
                    Text(Lf("search.limit", viewModel.hitLimit)).font(.caption2).foregroundStyle(Palette.ink3)
                }
            }
            .padding(20)
        }
    }

    private func isChecked(_ hit: SearchHit) -> Bool {
        evidence.checkedPlaces(of: hit.sourceID).contains(hit.place.key)
    }

    private func row(_ hit: SearchHit) -> some View {
        let place = hit.place
        let checked = isChecked(hit)
        // A passage that is already a quote opens that quote instead of making a second one.
        let saved = evidence.savedQuote(sourceID: hit.sourceID, text: place.quoteText, excluding: nil)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button { viewModel.open(hit) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Lf("evidence.occurrences.page", place.page + 1))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Palette.ink2)
                        .frame(width: 44, alignment: .trailing)
                    snippet(place)
                        .font(.callout)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("evidence.occurrences.open"))
            Button {
                onQuote(saved ?? EvidenceQuote(
                    text: place.quoteText,
                    sourceID: hit.sourceID,
                    locator: Lf("evidence.occurrences.page", place.page + 1)
                ))
            } label: {
                Image(systemName: saved == nil ? "quote.opening" : "quote.closing")
                    .foregroundStyle(saved == nil ? Palette.ink2 : Palette.accent)
            }
            .buttonStyle(.borderless)
            .help(saved == nil ? L("evidence.occurrences.save") : L("evidence.occurrences.saved"))
            Button {
                evidence.setChecked(!checked, key: place.key, sourceID: hit.sourceID)
            } label: {
                Image(systemName: checked ? "checkmark.circle.fill" : "checkmark.circle")
                    .foregroundStyle(checked ? Palette.accent : Palette.ink3)
            }
            .buttonStyle(.borderless)
            .help(checked ? L("evidence.occurrences.uncheck") : L("evidence.occurrences.check"))
        }
        .opacity(checked ? 0.55 : 1)
        .padding(.vertical, 4)
    }

    /// The words around the match, with the match itself in bold.
    private func snippet(_ place: TermOccurrence) -> Text {
        Text("…" + place.before).foregroundColor(Palette.ink2)
            + Text(place.text).bold().foregroundColor(Palette.ink)
            + Text(place.after + "…").foregroundColor(Palette.ink2)
    }
}
