import SwiftUI
import XuejiCore

/// A place to write free text and copy it out (to Word, an email, anywhere).
/// The sources the text is based on live in a panel on the right, so the writing area keeps its size.
struct WritingView: View {
    let viewModel: any IWritingViewModel
    @State private var isPickingCard = false
    @State private var pickerQuery = ""
    @State private var noteText = ""
    @State private var sourceQuery = ""
    @AppStorage("writing.showSources") private var showSources = true

    var body: some View {
        Group {
            if viewModel.drafts.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    list
                        .frame(width: 230)
                    Divider()
                    editor
                }
            }
        }
        .background(Palette.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) { deletedBanner }
        .navigationTitle(L("writing.title"))
        .navigationSubtitle(L("writing.subtitle"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { viewModel.newDraft() } label: {
                    Label(L("writing.new"), systemImage: "square.and.pencil")
                }
                .help(L("writing.new"))
                if let draft = viewModel.selectedDraft {
                    Button { viewModel.copy(draftID: draft.id) } label: {
                        Label(viewModel.justCopied ? L("writing.copied") : L("writing.copy"),
                              systemImage: viewModel.justCopied ? "checkmark" : "doc.on.clipboard")
                    }
                    .help(L("writing.copy"))
                    Button { showSources.toggle() } label: {
                        Label(L("writing.sources.toggle"), systemImage: "sidebar.right")
                    }
                    .help(L("writing.sources.toggle"))
                }
            }
        }
        .onAppear {
            if viewModel.selectedDraft == nil { viewModel.select(draftID: viewModel.drafts.first?.id) }
        }
        .onChange(of: viewModel.selectedDraft?.id) { _, _ in
            sourceQuery = ""
            noteText = ""
        }
    }

    // MARK: Pieces

    /// A deleted draft can be brought back from here until the next deletion.
    @ViewBuilder
    private var deletedBanner: some View {
        if let title = viewModel.deletedDraftTitle {
            HStack(spacing: 10) {
                Image(systemName: "trash").foregroundStyle(Palette.ink3)
                Text(Lf("writing.deleted", title)).font(.callout).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer()
                Button(L("board.undo")) { viewModel.undoDelete() }
                Button { viewModel.dismissDeleteNotice() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.ink3)
            }
            .padding(12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Palette.ink3)
            Text(L("writing.empty.title"))
                .font(.heading(.title2).weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(L("writing.empty.description"))
                .foregroundStyle(Palette.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button(L("writing.new")) { viewModel.newDraft() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.drafts) { draft in
                    let isSelected = draft.id == viewModel.selectedDraft?.id
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.title.isEmpty ? L("writing.untitled") : draft.title)
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(draft.text.isEmpty ? L("writing.emptyDraft") : draft.text)
                            .font(.caption)
                            .foregroundStyle(Palette.ink3)
                            .lineLimit(2)
                        Text(draft.updatedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localization.locale)))
                            .font(.caption2)
                            .foregroundStyle(Palette.ink3)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isSelected ? Palette.accentLight : Color.clear,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.select(draftID: draft.id) }
                    .contextMenu {
                        Button(L("writing.delete"), role: .destructive) { viewModel.delete(draftID: draft.id) }
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: Sources panel

    /// The cards (and then the notes) the text is based on, with one search over all of them.
    private func sourcesPanel(_ draft: Draft) -> some View {
        let phrase = TextSearch.normalized(sourceQuery)
        let searched = !phrase.isEmpty && !viewModel.isSearchingSources && viewModel.searchedPhrase == phrase
        let hits = searched ? viewModel.sourceHits : []
        let hitsByCard = Dictionary(grouping: hits.filter { $0.itemID != nil }, by: { $0.itemID! })
        var cards = viewModel.linkedCards(of: draft)
        if searched {
            cards = cards.enumerated()
                .sorted { a, b in
                    let (x, y) = (hitsByCard[a.element.id]?.count ?? 0, hitsByCard[b.element.id]?.count ?? 0)
                    return x != y ? x > y : a.offset < b.offset
                }
                .map(\.element)
        }
        let notes = viewModel.notes(of: draft)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label(L("writing.basis"), systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink2)
                Spacer()
                Button { isPickingCard = true } label: { Label(L("writing.basis.browse"), systemImage: "plus") }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $isPickingCard, arrowEdge: .bottom) { picker(draft) }
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            searchField(draft)
                .padding(.horizontal, 12).padding(.bottom, 10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if cards.isEmpty && notes.isEmpty {
                        Text(L("writing.sources.empty"))
                            .font(.caption)
                            .foregroundStyle(Palette.ink3)
                            .padding(.vertical, 8)
                    }
                    if searched, !phrase.isEmpty, hits.isEmpty {
                        Text(L("writing.search.none")).font(.caption).foregroundStyle(Palette.ink3)
                    }
                    ForEach(cards) { card in
                        sourceCard(card, draftID: draft.id, hits: hitsByCard[card.id] ?? [], phrase: phrase, searched: searched)
                    }
                    if !notes.isEmpty {
                        Text(L("writing.sources.notes"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.ink3)
                            .padding(.top, 4)
                        ForEach(Array(notes.enumerated()), id: \.offset) { index, note in
                            noteRow(note, index: index, draftID: draft.id, phrase: phrase, searched: searched)
                        }
                    }
                }
                .padding(12)
            }
            Divider()
            TextField(L("writing.basis.field"), text: $noteText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    viewModel.addNote(noteText, draftID: draft.id)
                    noteText = ""
                }
                .padding(12)
        }
        .background(Palette.surfaceAlt.opacity(0.5))
    }

    private func searchField(_ draft: Draft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.ink3)
                TextField(L("writing.search.field"), text: $sourceQuery)
                    .textFieldStyle(.plain)
                    .onChange(of: sourceQuery) { _, text in viewModel.searchSources(text, draftID: draft.id) }
                if viewModel.isSearchingSources { ProgressView().controlSize(.small) }
                if !sourceQuery.isEmpty {
                    Button { sourceQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.ink3) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
            .onChange(of: draft.linkedItemIDs) { _, _ in viewModel.searchSources(sourceQuery, draftID: draft.id) }
            .onChange(of: draft.basis) { _, _ in viewModel.searchSources(sourceQuery, draftID: draft.id) }
            if sourceQuery.isEmpty {
                Text(L("writing.sources.searchHint")).font(.caption2).foregroundStyle(Palette.ink3)
            }
        }
    }

    /// One source as a small card: what it is, how to open it, and (while searching) where the phrase was found.
    private func sourceCard(_ card: Item, draftID: UUID, hits: [SourceHit], phrase: String, searched: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: card.kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 22, height: 22)
                    .background(Palette.accentLight, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(.callout.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                    Text(viewModel.detail(of: card)).font(.caption).foregroundStyle(Palette.ink3).lineLimit(1)
                }
                Spacer(minLength: 0)
                if searched, !hits.isEmpty {
                    Text("\(hits.count)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Palette.accentLight, in: Capsule())
                        .foregroundStyle(Palette.accent)
                }
            }
            HStack(spacing: 10) {
                if viewModel.opensInReader(card) {
                    Text(L("writing.search.origin.pdf"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Palette.ink3)
                }
                Spacer()
                if viewModel.canCite(card) {
                    Button { viewModel.copyCitation(cardID: card.id) } label: {
                        Label(L("writing.cite"), systemImage: "quote.opening")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help(L("writing.cite.help"))
                }
                Button { viewModel.showCard(itemID: card.id) } label: {
                    Label(viewModel.opensInReader(card) ? L("library.read") : L("writing.search.openCard"),
                          systemImage: viewModel.opensInReader(card) ? "book" : "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help(viewModel.opensInReader(card) ? L("writing.basis.openPDF") : L("writing.basis.open"))
                Button { viewModel.unlink(cardID: card.id, draftID: draftID) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.ink3)
                }
                .buttonStyle(.plain)
                .help(L("writing.basis.remove"))
            }
            ForEach(hits) { hit in hitRow(hit, draftID: draftID, phrase: phrase) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
        .opacity(searched && hits.isEmpty ? 0.45 : 1)
    }

    private func hitRow(_ hit: SourceHit, draftID: UUID, phrase: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button { viewModel.open(hit: hit) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(label(of: hit), systemImage: symbol(of: hit.origin))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Palette.accent)
                    marked(hit.excerpt, phrase: phrase)
                        .font(.caption)
                        .foregroundStyle(Palette.ink2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L(hit.origin == .card ? "writing.search.openCard" : "writing.search.openPage"))
            if hit.origin == .pdf {
                Button(L("writing.search.quote")) { viewModel.insertQuote(hit: hit, draftID: draftID) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help(L("writing.search.quote.help"))
            }
        }
        .padding(8)
        .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func noteRow(_ note: String, index: Int, draftID: UUID, phrase: String, searched: Bool) -> some View {
        let matches = searched && TextSearch.contains(phrase, in: note)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.quote").foregroundStyle(Palette.ink3).font(.caption)
            (matches ? marked(note, phrase: phrase) : Text(note))
                .font(.caption)
                .foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { viewModel.removeNote(at: index, draftID: draftID) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.ink3)
            }
            .buttonStyle(.plain)
            .help(L("writing.basis.remove"))
        }
        .padding(10)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
        .opacity(searched && !matches ? 0.45 : 1)
    }

    private func symbol(of origin: SourceHit.Origin) -> String {
        switch origin {
        case .card: return "rectangle.on.rectangle"
        case .pdf: return "doc.text"
        case .readerNote: return "highlighter"
        case .basisNote: return "text.quote"
        }
    }

    private func label(of hit: SourceHit) -> String {
        switch hit.origin {
        case .card: return L("writing.search.origin.card")
        case .pdf: return hit.pageLabel.map { Lf("writing.search.page", $0) } ?? L("writing.search.origin.pdf")
        case .readerNote:
            return L("writing.search.origin.readerNote") + (hit.pageLabel.map { " · " + Lf("writing.search.page", $0) } ?? "")
        case .basisNote: return L("writing.search.origin.note")
        }
    }

    /// The excerpt with the searched phrase in bold on a soft yellow background.
    private func marked(_ excerpt: String, phrase: String) -> Text {
        var text = AttributedString(excerpt)
        var cursor = excerpt.startIndex
        while !phrase.isEmpty, cursor < excerpt.endIndex,
              let found = excerpt.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive], range: cursor..<excerpt.endIndex) {
            if let lower = AttributedString.Index(found.lowerBound, within: text),
               let upper = AttributedString.Index(found.upperBound, within: text) {
                text[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
                text[lower..<upper].backgroundColor = Color.yellow.opacity(0.35)
            }
            cursor = found.upperBound
        }
        return Text(text)
    }

    private func picker(_ draft: Draft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("writing.basis.search"), text: $pickerQuery)
                .textFieldStyle(.roundedBorder)
            let candidates = viewModel.candidateCards(for: draft, matching: pickerQuery)
            if candidates.isEmpty {
                Text(L("writing.basis.none")).font(.caption).foregroundStyle(Palette.ink3).padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(candidates) { card in
                            Button {
                                viewModel.link(cardID: card.id, draftID: draft.id)
                                isPickingCard = false
                                pickerQuery = ""
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Label(card.title, systemImage: card.kind.symbol).lineLimit(1)
                                    Text(viewModel.detail(of: card)).font(.caption2).foregroundStyle(Palette.ink3)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4).padding(.horizontal, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if let draft = viewModel.selectedDraft {
            HStack(spacing: 0) {
                writingColumn(draft)
                if showSources {
                    Divider()
                    sourcesPanel(draft).frame(width: 320)
                }
            }
        } else {
            Text(L("writing.pick")).foregroundStyle(Palette.ink3).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func writingColumn(_ draft: Draft) -> some View {
        let cardCount = viewModel.linkedCards(of: draft).count
        let noteCount = viewModel.notes(of: draft).count
        return VStack(alignment: .leading, spacing: 10) {
            TextField(L("writing.titlePlaceholder"), text: Binding(
                get: { draft.title }, set: { viewModel.setTitle($0, draftID: draft.id) }
            ))
            .textFieldStyle(.plain)
            .font(.heading(.title).weight(.bold))
            Button { showSources.toggle() } label: {
                Label(
                    cardCount + noteCount == 0 ? L("writing.sources.none") : Lf("writing.sources.summary", cardCount, noteCount),
                    systemImage: "link"
                )
                .font(.subheadline)
                .foregroundStyle(Palette.ink2)
            }
            .buttonStyle(.plain)
            .help(L("writing.sources.toggle"))
            TextEditor(text: Binding(
                get: { draft.text }, set: { viewModel.setText($0, draftID: draft.id) }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border))
            HStack {
                Text(Lf("writing.counts", viewModel.wordCount(of: draft), viewModel.characterCount(of: draft)))
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                Spacer()
                Button(L("writing.delete"), role: .destructive) { viewModel.delete(draftID: draft.id) }
                    .buttonStyle(.bordered)
                Menu(L("writing.export")) {
                    ForEach(DraftFormat.allCases) { format in
                        Button(L("writing.export." + format.rawValue)) {
                            viewModel.export(draftID: draft.id, format: format)
                        }
                    }
                }
                .fixedSize()
                Menu {
                    Button(L("writing.copyWithSources")) { viewModel.copyWithSources(draftID: draft.id) }
                } label: {
                    Label(viewModel.justCopied ? L("writing.copied") : L("writing.copy"),
                          systemImage: viewModel.justCopied ? "checkmark" : "doc.on.clipboard")
                } primaryAction: {
                    viewModel.copy(draftID: draft.id)
                }
                .menuStyle(.borderedButton)
                .fixedSize()
            }
        }
        .padding(20)
    }
}
