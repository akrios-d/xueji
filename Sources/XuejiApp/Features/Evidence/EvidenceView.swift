import Charts
import SwiftUI
import XuejiCore

/// The triage of a project: how often a term appears in the sources, the strongest quotes sorted by
/// importance, a timeline and the findings, ready to export.
struct EvidenceView: View {
    let viewModel: any IEvidenceViewModel
    let search: any IEvidenceSearchViewModel

    private enum Tab: String, CaseIterable, Identifiable {
        case counts, search, quotes, timeline, findings, report
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .counts: return "number"
            case .search: return "magnifyingglass"
            case .quotes: return "quote.opening"
            case .timeline: return "calendar.day.timeline.left"
            case .findings: return "text.alignleft"
            case .report: return "doc.richtext"
            }
        }
    }

    @AppStorage("evidenceTab") private var tabName = Tab.counts.rawValue
    @State private var editingQuote: EvidenceQuote?
    @State private var editingEvent: EvidenceEvent?
    @State private var editingEra: EvidenceEra?
    @State private var editingMaster = false
    @State private var isChoosingReport = false
    /// Also list the documents that have nothing to look for.
    @AppStorage("evidenceShowEmptyDocuments") private var showEmptyDocuments = false
    /// The event picked on the chart or in the list.
    @State private var selectedEvent: UUID?
    @State private var confirmingDelete = false
    /// The PDF shown on the Documents tab.
    /// Kept between visits, so coming back from the reader lands on the same PDF.
    @AppStorage("evidenceSelectedSource") private var selectedSourceRaw = ""
    private var selectedSource: UUID? {
        get { UUID(uuidString: selectedSourceRaw) }
        nonmutating set { selectedSourceRaw = newValue?.uuidString ?? "" }
    }
    @State private var showingModifierInfo = false

    private var tab: Tab { Tab(rawValue: tabName) ?? .counts }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch tab {
                case .counts: counts
                case .search: EvidenceSearchTab(viewModel: search, evidence: viewModel) { editingQuote = $0 }
                case .quotes: quotes
                case .timeline: timeline
                case .findings: findings
                case .report: if isEmpty { emptyReport } else { report }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.bg)
        .navigationTitle(L("evidence.title"))
        .navigationSubtitle(L("evidence.subtitle"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { isChoosingReport = true } label: {
                    Label(L("evidence.import"), systemImage: "square.and.arrow.down")
                }
                .help(L("evidence.import.help"))
                Button { viewModel.copyReport() } label: {
                    Label(viewModel.justCopied ? L("compile.copied") : L("compile.copy"),
                          systemImage: viewModel.justCopied ? "checkmark" : "doc.on.clipboard")
                }
                .help(L("compile.copy"))
                .disabled(isEmpty)
                Menu {
                    ForEach(EvidenceFormat.allCases) { format in
                        Button(L("evidence.export." + format.rawValue)) { viewModel.export(format: format) }
                    }
                } label: {
                    Label(L("compile.export"), systemImage: "square.and.arrow.up")
                }
                .help(L("compile.export"))
                .disabled(isEmpty)
            }
        }
        .fileImporter(isPresented: $isChoosingReport, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { viewModel.importReport(at: url) }
        }
        .sheet(item: $editingQuote) { quote in
            QuoteForm(viewModel: viewModel, quote: quote) { editingQuote = nil }
        }
        .sheet(isPresented: $editingMaster) {
            MasterForm(viewModel: viewModel) { editingMaster = false }
        }
        .sheet(item: $editingEra) { era in
            EraForm(viewModel: viewModel, era: era) { editingEra = nil }
        }
        .sheet(item: $editingEvent) { event in
            EventForm(viewModel: viewModel, event: event) { editingEvent = nil }
        }
        .task { viewModel.refresh() }
    }

    /// Nothing has been counted, quoted or placed on the timeline yet, so there is no report to show.
    private var isEmpty: Bool {
        viewModel.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && viewModel.quotes.isEmpty && viewModel.events.isEmpty && viewModel.eras.isEmpty && viewModel.masterTitle == L("evidence.timeline.master")
    }

    private var emptyReport: some View {
        VStack(spacing: 18) {
            Image(systemName: "quote.bubble").font(.system(size: 36)).foregroundStyle(Palette.ink3)
            Text(L("evidence.empty.title")).font(.sectionTitle).foregroundStyle(Palette.ink)
            Text(L("evidence.empty.text"))
                .font(.callout).foregroundStyle(Palette.ink2).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                Label(L("evidence.empty.step1"), systemImage: "1.circle")
                Label(L("evidence.empty.step2"), systemImage: "2.circle")
                Label(L("evidence.empty.step3"), systemImage: "3.circle")
            }
            .font(.callout).foregroundStyle(Palette.ink)
            Button(L("evidence.empty.start")) { tabName = Tab.counts.rawValue }
                .buttonStyle(.borderedProminent)
            Text(L("evidence.empty.import")).font(.caption).foregroundStyle(Palette.ink3).multilineTextAlignment(.center)
        }
        .frame(maxWidth: 460)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                evidenceMenu
                TextField(L("evidence.titlePlaceholder"), text: Binding(
                    get: { viewModel.title }, set: { viewModel.setTitle($0) }
                ))
                .textFieldStyle(.plain)
                .font(.heading(.title3).weight(.bold))
            }
            Picker("", selection: $tabName) {
                ForEach(Tab.allCases) { tab in
                    Label(L("evidence.tab." + tab.rawValue), systemImage: tab.symbol).tag(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 720)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var evidenceMenu: some View {
        Menu {
            ForEach(viewModel.evidenceList) { item in
                Button {
                    viewModel.selectEvidence(id: item.id)
                } label: {
                    if item.isActive { Label(item.name, systemImage: "checkmark") } else { Text(item.name) }
                }
            }
            if !viewModel.evidenceList.isEmpty { Divider() }
            Button(L("evidence.new")) { viewModel.addEvidence() }
            Button(L("evidence.deleteThis"), role: .destructive) { confirmingDelete = true }
                .disabled(viewModel.evidenceList.isEmpty)
        } label: {
            Label(L("evidence.switch"), systemImage: "rectangle.stack")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L("evidence.switch.help"))
        .confirmationDialog(L("evidence.deleteThis.confirm"), isPresented: $confirmingDelete) {
            Button(L("evidence.delete"), role: .destructive) { viewModel.deleteCurrentEvidence() }
        }
    }

    // MARK: Documents (the "counts" tab)

    private var counts: some View {
        // Only real documents are listed: a source without a PDF here has nothing to read, count or quote.
        let rows = viewModel.rows.filter(\.hasPDF)
        let term = viewModel.term.trimmingCharacters(in: .whitespacesAndNewlines)
        // A document with nothing to look for (the term is not in it, or it is left out) is not listed unless asked.
        let withTerm = rows.filter { hasTerm($0, term: term) }
        let without = rows.filter { !hasTerm($0, term: term) }
        let shown = showEmptyDocuments ? withTerm + without : withTerm
        return VStack(spacing: 0) {
            termBar
            Divider()
            if rows.isEmpty {
                Text(L("evidence.noSources")).foregroundStyle(Palette.ink3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    documentList(shown, hiddenCount: showEmptyDocuments ? 0 : without.count, canHide: showEmptyDocuments && !without.isEmpty)
                        .frame(width: 300)
                    Divider()
                    if shown.isEmpty, !viewModel.isCounting {
                        Text(L("evidence.docs.noneHave")).foregroundStyle(Palette.ink3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        detail(shown)
                    }
                }
            }
        }
        .onAppear { keepSelectionListed(in: shown) }
        .onChange(of: shown.map(\.id)) { _, _ in keepSelectionListed(in: shown) }
    }

    /// True when there is something to look for in the document: no term typed yet, or the term is in it (or its PDF
    /// is still being read).
    private func hasTerm(_ row: EvidenceSourceRow, term: String) -> Bool {
        if term.isEmpty { return true }
        if let count = row.count { return count.term > 0 }
        return row.included && row.hasPDF
    }

    /// The document shown on the right is always one of those in the list.
    private func keepSelectionListed(in shown: [EvidenceSourceRow]) {
        if let selected = selectedSource, shown.contains(where: { $0.id == selected }) { return }
        selectedSource = shown.first(where: { $0.hasPDF && !$0.isFixed })?.id ?? shown.first?.id
    }

    /// Step 1: the word to look for.
    private var termBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                labeled(L("evidence.term")) {
                    TextField(L("evidence.term.placeholder"), text: Binding(
                        get: { viewModel.term }, set: { viewModel.setTerm($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(L("evidence.modifier")).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
                        Button { showingModifierInfo.toggle() } label: {
                            Image(systemName: "info.circle").foregroundStyle(Palette.ink3)
                        }
                        .buttonStyle(.plain)
                        .help(L("evidence.modifier.info.help"))
                        .popover(isPresented: $showingModifierInfo, arrowEdge: .bottom) {
                            Text(L("evidence.modifier.info"))
                                .font(.callout)
                                .frame(width: 320, alignment: .leading)
                                .padding(14)
                        }
                    }
                    TextField(L("evidence.modifier.placeholder"), text: Binding(
                        get: { viewModel.modifier }, set: { viewModel.setModifier($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                if viewModel.isCounting { ProgressView().controlSize(.small) }
            }
            Text(L("evidence.term.hint")).font(.caption).foregroundStyle(Palette.ink3)
            if let phrase = modifierPhrase {
                Text(Lf("evidence.modifier.preview", phrase)).font(.caption).foregroundStyle(Palette.ink2)
            }
            DisclosureGroup(L("evidence.notes")) {
                VStack(alignment: .leading, spacing: 10) {
                    labeled(L("evidence.corpusNote")) {
                        TextField(L("evidence.corpusNote.placeholder"), text: Binding(
                            get: { viewModel.corpusNote }, set: { viewModel.setCorpusNote($0) }
                        ), axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                    }
                    labeled(L("evidence.caution")) {
                        TextField(L("evidence.caution.placeholder"), text: Binding(
                            get: { viewModel.caution }, set: { viewModel.setCaution($0) }
                        ), axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.top, 6)
            }
            .font(.callout)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    /// The phrase counted besides the term, when a modifier is typed.
    private var modifierPhrase: String? {
        let lead = viewModel.modifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let word = viewModel.term.trimmingCharacters(in: .whitespacesAndNewlines)
        return lead.isEmpty || word.isEmpty ? nil : lead + " " + word
    }

    /// Step 2: pick a PDF.
    private func documentList(_ rows: [EvidenceSourceRow], hiddenCount: Int, canHide: Bool) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { row.included && row.hasPDF }, set: { viewModel.setIncluded($0, sourceID: row.id) }
                        ))
                        .labelsHidden()
                        .disabled(!row.hasPDF)
                        .help(L("evidence.include.help"))
                        Button { selectedSource = row.id } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Text(row.title).font(.callout).foregroundStyle(Palette.ink).lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let count = row.count, row.included, row.hasPDF {
                                    Text("\(count.term)")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(count.term > 0 ? Palette.accent : Palette.ink3)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(
                        selectedSource == row.id ? Palette.accentLight : Color.clear,
                        in: RoundedRectangle(cornerRadius: Radius.sm)
                    )
                    .opacity(row.included && row.hasPDF ? 1 : 0.55)
                }
                if hiddenCount > 0 || canHide {
                    Button { showEmptyDocuments.toggle() } label: {
                        Text(canHide ? L("evidence.docs.hideEmpty") : Lf("evidence.docs.showEmpty", hiddenCount))
                            .font(.caption).foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 10)
                }
            }
            .padding(8)
        }
    }

    /// Step 3: where the term appears in the chosen PDF.
    @ViewBuilder
    private func detail(_ rows: [EvidenceSourceRow]) -> some View {
        if let row = rows.first(where: { $0.id == selectedSource }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title).font(.sectionTitle).foregroundStyle(Palette.ink)
                        Spacer(minLength: 8)
                        if row.hasPDF, !row.isFixed {
                            Button(L("evidence.openPDF")) { viewModel.openSource(id: row.id) }
                        }
                    }
                    countSummary(row)
                    HStack(spacing: 8) {
                        TextField(L("evidence.date"), text: Binding(
                            get: { row.date }, set: { viewModel.setDate($0, sourceID: row.id) }
                        ))
                        .frame(width: 110)
                        TextField(L("evidence.usage"), text: Binding(
                            get: { row.usage }, set: { viewModel.setUsage($0, sourceID: row.id) }
                        ))
                    }
                    .textFieldStyle(.roundedBorder)
                    if row.hasPDF, !row.isFixed, row.included {
                        if viewModel.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(L("evidence.typeTerm")).font(.callout).foregroundStyle(Palette.ink3)
                        } else {
                            OccurrencesList(viewModel: viewModel, row: row) {
                                editingQuote = $0
                            }
                                .id(row.id)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(L("evidence.pick")).foregroundStyle(Palette.ink3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func countSummary(_ row: EvidenceSourceRow) -> some View {
        if !row.hasPDF {
            Text(L("evidence.noPDF")).font(.caption).foregroundStyle(Palette.ink3)
        } else if !row.included {
            Text(L("evidence.excluded")).font(.caption).foregroundStyle(Palette.ink3)
        } else if let count = row.count {
            if row.isFixed {
                Text(Lf("evidence.countLine.imported", count.term, String(format: "%.2f", TermCounter.perThousand(count.term, words: count.words)), count.words))
                    .font(.caption.monospacedDigit()).foregroundStyle(Palette.ink2)
            } else if count.hasText {
                Text(Lf("evidence.countLine", count.term, String(format: "%.2f", TermCounter.perThousand(count.term, words: count.words)), count.words))
                    .font(.caption.monospacedDigit()).foregroundStyle(Palette.ink2)
            } else {
                Label(L("evidence.noText"), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Palette.ink2)
            }
        } else {
            ProgressView().controlSize(.mini)
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
            content()
        }
    }

    // MARK: Quotes

    private var quotes: some View {
        let quotes = viewModel.quotes
        return VStack(spacing: 0) {
            HStack {
                Text(Lf("evidence.quotes.count", quotes.count)).font(.subheadline).foregroundStyle(Palette.ink2)
                Spacer()
                Text(L("evidence.quotes.hint")).font(.caption).foregroundStyle(Palette.ink3)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            Divider()
            if quotes.isEmpty {
                emptyText(L("evidence.quotes.empty"))
            } else {
                List {
                    ForEach(Array(quotes.enumerated()), id: \.element.id) { index, quote in
                        quoteRow(quote, number: index + 1, isFirst: index == 0, isLast: index == quotes.count - 1)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func quoteRow(_ quote: EvidenceQuote, number: Int, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(Palette.ink3).frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 5) {
                Text("“\(quote.text)”").font(.callout).foregroundStyle(Palette.ink).lineLimit(4)
                let origin = [quote.speaker, viewModel.sourceTitle(quote.sourceID), quote.locator].filter { !$0.isEmpty }
                if !origin.isEmpty {
                    Text(origin.joined(separator: " · ")).font(.caption).foregroundStyle(Palette.ink2)
                }
                if !quote.why.isEmpty {
                    Text(quote.why).font(.caption).foregroundStyle(Palette.ink3).lineLimit(3)
                }
            }
            Spacer(minLength: 8)
            if let sourceID = quote.sourceID {
                Button { viewModel.openSource(id: sourceID, page: pageIndex(of: quote)) } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help(L("evidence.quote.show"))
            }
            kindBadge(quote.kind)
        }
        .padding(.vertical, 4)
        .padding(.trailing, 14)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editingQuote = quote }
        .contextMenu {
            if let sourceID = quote.sourceID {
                Button(L("evidence.quote.show")) { viewModel.openSource(id: sourceID, page: pageIndex(of: quote)) }
                Divider()
            }
            Button(L("evidence.edit")) { editingQuote = quote }
            Button(L("compile.moveUp")) { viewModel.moveQuote(id: quote.id, by: -1) }.disabled(isFirst)
            Button(L("compile.moveDown")) { viewModel.moveQuote(id: quote.id, by: 1) }.disabled(isLast)
            Divider()
            Button(L("evidence.delete"), role: .destructive) { viewModel.deleteQuote(id: quote.id) }
        }
    }

    /// The zero-based page a quote came from, read from its locator ("p. 3"); the first page when it has none.
    private func pageIndex(of quote: EvidenceQuote) -> Int {
        let digits = quote.locator.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
        return max((Int(digits) ?? 1) - 1, 0)
    }

    private func kindBadge(_ kind: EvidenceKind) -> some View {
        Text(L("evidence.kind." + kind.rawValue))
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(kindColor(kind).opacity(0.18), in: Capsule())
            .foregroundStyle(kindColor(kind))
    }

    private func kindColor(_ kind: EvidenceKind) -> Color {
        switch kind {
        case .essential: return .green
        case .supporting: return .blue
        case .counter: return .orange
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        let events = viewModel.events
        let outline = viewModel.eraOutline
        let data = TimelineChartData.make(
            events: events, outline: outline, masterName: viewModel.masterTitle, title: { viewModel.sourceTitle($0) },
            quote: { quoteText($0) }, noDocument: L("evidence.timeline.noDocument")
        )
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(Lf("evidence.timeline.count", events.count)).font(.subheadline).foregroundStyle(Palette.ink2)
                Spacer()
                Button { viewModel.generateTimeline() } label: { Label(L("evidence.timeline.generate"), systemImage: "wand.and.stars") }
                    .help(L("evidence.timeline.generateHelp"))
                Button { editingEra = EvidenceEra() } label: { Label(L("evidence.timeline.addEra"), systemImage: "calendar.day.timeline.left") }
                Button { editingEvent = EvidenceEvent() } label: { Label(L("evidence.timeline.add"), systemImage: "plus") }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            Divider()
            if events.isEmpty, outline.count <= 1 {
                emptyText(L("evidence.timeline.empty"))
            } else {
                if !data.items.isEmpty {
                    TimelineChart(data: data, selected: $selectedEvent)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                    Divider()
                }
                if data.undated > 0 {
                    Text(Lf("evidence.timeline.undated", data.undated))
                        .font(.caption).foregroundStyle(Palette.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.top, 8)
                }
                List {
                    ForEach(outline) { node in
                        Section {
                            ForEach(viewModel.events(in: node.era?.id)) { event in
                                eventRow(event).padding(.leading, CGFloat(node.depth + 1) * 18)
                            }
                        } header: {
                            eraHeader(node, span: data.years)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// The row that opens a period: the master (the whole timeline) or one of the periods inside it.
    private func eraHeader(_ node: EraNode, span: ClosedRange<Int>?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let era = node.era {
                Text(era.dateLabel).font(.callout.weight(.semibold)).foregroundStyle(Palette.accent).frame(width: 130, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(era.name).font(.callout.weight(.semibold)).foregroundStyle(Palette.ink)
                    ForEach(era.quoteIDs, id: \.self) { id in
                        let text = quoteText(id)
                        if !text.isEmpty {
                            Label("“\(text)”", systemImage: "quote.opening")
                                .font(.caption).foregroundStyle(Palette.accent).lineLimit(2)
                        }
                    }
                }
            } else {
                Text(span.map { EvidenceDate.label(from: EvidenceDate(year: $0.lowerBound), until: EvidenceDate(year: $0.upperBound)) } ?? "")
                    .font(.callout.weight(.semibold)).foregroundStyle(Palette.accent).frame(width: 130, alignment: .leading)
                Text(viewModel.masterTitle).font(.callout.weight(.semibold)).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
        .padding(.leading, CGFloat(node.depth) * 18)
        .padding(.horizontal, 6)
        .background(selectedEvent == node.id ? Palette.accentLight : Color.clear, in: RoundedRectangle(cornerRadius: Radius.sm))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if let era = node.era { editingEra = era } else { editingMaster = true }
        }
        .onTapGesture { selectedEvent = node.id }
        .contextMenu {
            if let era = node.era {
                Button(L("evidence.edit")) { editingEra = era }
                Button(L("evidence.timeline.addGroup")) {
                    editingEra = EvidenceEra(from: era.from, until: era.until, parentID: era.id)
                }
                Divider()
                Button(L("evidence.delete"), role: .destructive) { viewModel.deleteEra(id: era.id) }
            } else {
                Button(L("evidence.timeline.renameMaster")) { editingMaster = true }
                Button(L("evidence.timeline.addGroup")) { editingEra = EvidenceEra() }
            }
        }
    }

    /// The text of a quote of this report, for the timeline.
    private func quoteText(_ id: UUID?) -> String {
        guard let id else { return "" }
        return viewModel.quotes.first { $0.id == id }?.text ?? ""
    }

    private func eventRow(_ event: EvidenceEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.dateLabel).font(.callout.weight(.semibold)).foregroundStyle(Palette.ink).frame(width: 130, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.event).font(.callout).foregroundStyle(Palette.ink)
                if !event.who.isEmpty { Text(event.who).font(.caption).foregroundStyle(Palette.ink2) }
                let quote = quoteText(event.quoteID)
                if !quote.isEmpty {
                    Label("“\(quote)”", systemImage: "quote.opening")
                        .font(.caption).foregroundStyle(Palette.accent).lineLimit(2)
                }
                if !event.frame.isEmpty { Text(event.frame).font(.caption).foregroundStyle(Palette.ink3).lineLimit(3) }
            }
            Spacer(minLength: 8)
            if event.isGap {
                Text(L("evidence.gap")).font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.red.opacity(0.15), in: Capsule()).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(selectedEvent == event.id ? Palette.accentLight : Color.clear, in: RoundedRectangle(cornerRadius: Radius.sm))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editingEvent = event }
        .onTapGesture { selectedEvent = event.id }
        .contextMenu {
            Button(L("evidence.edit")) { editingEvent = event }
            Divider()
            Button(L("evidence.delete"), role: .destructive) { viewModel.deleteEvent(id: event.id) }
        }
    }

    // MARK: Findings

    private var findings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("evidence.findings.hint")).font(.callout).foregroundStyle(Palette.ink2)
            TextEditor(text: Binding(get: { viewModel.findings }, set: { viewModel.setFindings($0) }))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Palette.surfaceAlt.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
    }

    // MARK: Report

    private var report: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(viewModel.report.enumerated()), id: \.offset) { _, block in reportBlock(block) }
            }
            .textSelection(.enabled)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The report is as wide as its table, and the text above and below it wraps at that width instead of running
    /// off to the right.
    private let reportWidth: CGFloat = 1000

    @ViewBuilder
    private func reportBlock(_ block: ReportBlock) -> some View {
        switch block {
        case .title(let text):
            Text(text).font(.heading(.title).weight(.bold)).foregroundStyle(Palette.ink)
                .frame(width: reportWidth, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        case .subtitle(let text):
            Text(text).font(.caption).foregroundStyle(Palette.ink3)
                .frame(width: reportWidth, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        case .heading(let text):
            Text(text).font(.heading(.title3).weight(.semibold)).foregroundStyle(Palette.ink).padding(.top, 10)
                .frame(width: reportWidth, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        case .paragraph(let text):
            Text(text).font(.callout).foregroundStyle(Palette.ink2)
                .frame(width: reportWidth, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        case .callout(let text, _):
            Text(text).font(.callout).foregroundStyle(Palette.ink)
                .padding(10)
                .frame(width: reportWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        case .table(let columns, let rows):
            reportTable(columns, rows)
        }
    }

    private func reportTable(_ columns: [ReportColumn], _ rows: [[ReportCell]]) -> some View {
        let total = CGFloat(max(columns.reduce(0) { $0 + $1.weight }, 1))
        let width = reportWidth
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    Text(column.title).font(.caption.weight(.bold)).foregroundStyle(Palette.ink)
                        .padding(6)
                        .frame(width: width * CGFloat(column.weight) / total, alignment: .leading)
                }
            }
            .background(Palette.surfaceAlt)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        let cell = index < row.count ? row[index] : ReportCell("")
                        Text(cell.text).font(.caption.weight(cell.bold ? .bold : .regular)).foregroundStyle(Palette.ink)
                            .padding(6)
                            .frame(width: width * CGFloat(column.weight) / total, alignment: .leading)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                            .background(shadeColor(cell.shade))
                    }
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.border))
    }

    private func shadeColor(_ shade: ReportShade?) -> Color {
        switch shade {
        case .essential: return Color.green.opacity(0.18)
        case .supporting: return Color.blue.opacity(0.15)
        case .counter: return Color.orange.opacity(0.2)
        case .gap: return Color.red.opacity(0.12)
        case .note, .header, nil: return .clear
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Palette.ink3)
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Forms

private struct QuoteForm: View {
    let viewModel: any IEvidenceViewModel
    @State var quote: EvidenceQuote
    let done: () -> Void

    /// Another quote of the same document already holds this passage.
    private var isDuplicate: Bool {
        viewModel.savedQuote(sourceID: quote.sourceID, text: quote.text, excluding: quote.id) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("evidence.quote.title")).font(.heading(.title3).weight(.semibold))
            Text(L("evidence.quote.text")).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
            TextEditor(text: $quote.text)
                .frame(height: 96)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
            if quote.sourceID != nil {
                // Filled in by the app from the document and the page the quote was taken from.
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.sourceTitle(quote.sourceID)).foregroundStyle(Palette.ink)
                        .lineLimit(2).truncationMode(.middle)
                    if !quote.locator.isEmpty {
                        Text(quote.locator).font(.caption).foregroundStyle(Palette.ink2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Palette.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.sm))
                TextField(L("evidence.quote.speaker"), text: $quote.speaker)
            } else {
                // An imported quote whose document is not known.
                SourceMenu(title: L("evidence.quote.source"), viewModel: viewModel, selection: $quote.sourceID)
                TextField(L("evidence.quote.speaker"), text: $quote.speaker)
                TextField(L("evidence.quote.locator"), text: $quote.locator)
            }
            Picker(L("evidence.col.class"), selection: $quote.kind) {
                ForEach(EvidenceKind.allCases) { kind in Text(L("evidence.kind." + kind.rawValue)).tag(kind) }
            }
            .pickerStyle(.segmented)
            Text(L("evidence.col.why")).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
            TextEditor(text: $quote.why)
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
            if isDuplicate {
                Text(L("evidence.quote.duplicate")).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(L("evidence.cancel"), role: .cancel, action: done)
                    .keyboardShortcut(.cancelAction)
                Button(L("evidence.save")) {
                    viewModel.save(quote: quote)
                    done()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(quote.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDuplicate)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 520)
    }
}

/// What is typed in the fields of a date: a year, and optionally a month and a day.
private struct DateDraft: Equatable {
    var yearText = ""
    var month: Int?
    var dayText = ""

    init() {}

    init(_ date: EvidenceDate?) {
        yearText = date.map { String($0.year) } ?? ""
        month = date?.month
        dayText = date?.day.map(String.init) ?? ""
    }

    var isEmpty: Bool { yearText.isEmpty && dayText.isEmpty }

    /// The date the fields describe, or nil while it is empty or does not exist.
    var value: EvidenceDate? {
        guard let year = Int(yearText) else { return nil }
        let day = Int(dayText)
        guard dayText.isEmpty || (month != nil && day != nil) else { return nil }
        let date = EvidenceDate(year: year, month: month, day: month == nil ? nil : day)
        return date.isValid ? date : nil
    }

    var isInvalid: Bool { !isEmpty && value == nil }
}

/// A year, and optionally a month and a day: only dates that exist can be written.
private struct DateFields: View {
    let title: String
    @Binding var draft: DateDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
            HStack(spacing: 8) {
                TextField(L("evidence.event.year"), text: $draft.yearText)
                    .frame(width: 90)
                    .onChange(of: draft.yearText) { _, text in
                        let digits = String(text.filter(\.isNumber).prefix(4))
                        if digits != text { draft.yearText = digits }
                    }
                TextField(L("evidence.event.day"), text: $draft.dayText)
                    .frame(width: 70)
                    .disabled(draft.month == nil)
                    .onChange(of: draft.dayText) { _, text in
                        let digits = String(text.filter(\.isNumber).prefix(2))
                        if digits != text { draft.dayText = digits }
                    }
                if let value = draft.value {
                    Text(value.label).font(.callout.weight(.semibold)).foregroundStyle(Palette.accent)
                }
            }
            let names = Calendar.current.shortMonthSymbols
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(1...12, id: \.self) { number in
                    Button {
                        draft.month = draft.month == number ? nil : number
                        if draft.month == nil { draft.dayText = "" }
                    } label: {
                        Text(names[number - 1])
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .foregroundStyle(draft.month == number ? Color.white : Palette.ink)
                            .background(draft.month == number ? Palette.accent : Palette.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                            .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border))
                    }
                    .buttonStyle(.plain)
                }
            }
            if draft.isInvalid {
                Text(L("evidence.event.dateInvalid")).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

/// True when the dates, or the period they make, lie inside the period given (or when there is no period).
private func fits(_ from: EvidenceDate?, _ until: EvidenceDate?, inside era: EvidenceEra?) -> Bool {
    guard let era, let from else { return true }
    let tail = until ?? from
    return from.start >= era.from.start && tail.end <= era.until.end
}

/// True when the period ends before it begins.
private func endsBeforeStart(_ from: EvidenceDate?, _ until: EvidenceDate?) -> Bool {
    guard let from, let until else { return false }
    return until.start < from.start
}

private struct EventForm: View {
    let viewModel: any IEvidenceViewModel
    @State var event: EvidenceEvent
    @State private var from: DateDraft
    @State private var until: DateDraft
    @State private var isPeriod: Bool
    let done: () -> Void

    init(viewModel: any IEvidenceViewModel, event: EvidenceEvent, done: @escaping () -> Void) {
        self.viewModel = viewModel
        self.done = done
        _event = State(initialValue: event)
        _from = State(initialValue: DateDraft(event.position))
        _until = State(initialValue: DateDraft(event.until))
        _isPeriod = State(initialValue: event.until != nil)
    }

    private var era: EvidenceEra? { viewModel.eras.first { $0.id == event.eraID } }

    private var fitsEra: Bool {
        fits(from.value, isPeriod ? until.value : nil, inside: era)
    }

    private var isValid: Bool {
        guard let start = from.value else { return false }
        if isPeriod {
            guard let end = until.value, !endsBeforeStart(start, end) else { return false }
        }
        return fitsEra
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("evidence.event.title")).font(.heading(.title3).weight(.semibold))
            EraChooser(title: L("evidence.event.era"), viewModel: viewModel, selection: $event.eraID, excluding: [])
            DateFields(title: L("evidence.col.date"), draft: $from)
            Toggle(L("evidence.event.period"), isOn: $isPeriod)
                .onChange(of: isPeriod) { _, on in if on, until.isEmpty { until = from } }
            if isPeriod {
                DateFields(title: L("evidence.event.until"), draft: $until)
                if endsBeforeStart(from.value, until.value) {
                    Text(L("evidence.event.periodOrder")).font(.caption).foregroundStyle(.red)
                }
            }
            if !fitsEra, let era {
                Text(Lf("evidence.event.outsideEra", era.name, era.dateLabel)).font(.caption).foregroundStyle(.red)
            }
            TextField(L("evidence.col.event"), text: $event.event)
            TextField(L("evidence.col.who"), text: $event.who)
            Text(L("evidence.col.frame")).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
            TextEditor(text: $event.frame)
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
            Toggle(L("evidence.event.gap"), isOn: $event.isGap)
                .onChange(of: event.isGap) { _, isGap in if isGap { event.quoteID = nil } }
            QuoteChooser(title: L("evidence.event.quote"), viewModel: viewModel, selection: $event.quoteID)
                .disabled(event.isGap)
                .onChange(of: event.quoteID) { _, id in
                    // The document of the quote is the source of the event.
                    guard let id, let quote = viewModel.quotes.first(where: { $0.id == id }) else { return }
                    event.sourceID = quote.sourceID
                }
            SourceMenu(title: L("evidence.event.source"), viewModel: viewModel, selection: $event.sourceID)
                .disabled(event.isGap || event.quoteID != nil)
                .onChange(of: event.sourceID) { _, id in
                    // The date of the document fills the date of the line, unless the student already chose one.
                    guard from.isEmpty, let id, let row = viewModel.rows.first(where: { $0.id == id }),
                          let parsed = EvidenceDate.parse(row.date) else { return }
                    from = DateDraft(parsed)
                }
            HStack {
                Spacer()
                Button(L("evidence.cancel"), role: .cancel, action: done)
                    .keyboardShortcut(.cancelAction)
                Button(L("evidence.save")) {
                    guard let start = from.value else { return }
                    event.when = start
                    event.until = isPeriod ? until.value : nil
                    event.date = EvidenceDate.label(from: start, until: event.until)
                    viewModel.save(event: event)
                    done()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 520)
    }
}

/// A named period of the timeline, and the quotes that belong to it.
private struct EraForm: View {
    let viewModel: any IEvidenceViewModel
    @State var era: EvidenceEra
    @State private var from: DateDraft
    @State private var until: DateDraft
    let done: () -> Void

    init(viewModel: any IEvidenceViewModel, era: EvidenceEra, done: @escaping () -> Void) {
        self.viewModel = viewModel
        self.done = done
        _era = State(initialValue: era)
        _from = State(initialValue: DateDraft(era.from))
        _until = State(initialValue: DateDraft(era.until))
    }

    private var parent: EvidenceEra? { viewModel.eras.first { $0.id == era.parentID } }

    private var fitsParent: Bool { fits(from.value, until.value, inside: parent) }

    /// The period itself and the ones inside it cannot be its parent.
    private var cannotHold: Set<UUID> {
        viewModel.eraOutline.descendantIDs(of: era.id).union([era.id])
    }

    private var isValid: Bool {
        guard let start = from.value, let end = until.value else { return false }
        return !era.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !endsBeforeStart(start, end) && fitsParent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("evidence.era.title")).font(.heading(.title3).weight(.semibold))
            TextField(L("evidence.era.name"), text: $era.name)
            EraChooser(title: L("evidence.era.parent"), viewModel: viewModel, selection: $era.parentID, excluding: cannotHold)
            DateFields(title: L("evidence.era.from"), draft: $from)
            DateFields(title: L("evidence.era.until"), draft: $until)
            if endsBeforeStart(from.value, until.value) {
                Text(L("evidence.event.periodOrder")).font(.caption).foregroundStyle(.red)
            }
            if !fitsParent, let parent {
                Text(Lf("evidence.era.outside", parent.name, parent.dateLabel)).font(.caption).foregroundStyle(.red)
            }
            Text(L("evidence.era.quotes")).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
            if viewModel.quotes.isEmpty {
                Text(L("evidence.era.noQuotes")).font(.caption).foregroundStyle(Palette.ink3)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.quotes) { quote in
                            let isOn = era.quoteIDs.contains(quote.id)
                            Button {
                                if isOn { era.quoteIDs.removeAll { $0 == quote.id } } else { era.quoteIDs.append(quote.id) }
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(isOn ? Palette.accent : Palette.ink3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(quote.text).foregroundStyle(Palette.ink).lineLimit(2).multilineTextAlignment(.leading)
                                        Text(viewModel.sourceTitle(quote.sourceID)).font(.caption).foregroundStyle(Palette.ink3).lineLimit(1)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(height: 150)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
            }
            HStack {
                Spacer()
                Button(L("evidence.cancel"), role: .cancel, action: done)
                    .keyboardShortcut(.cancelAction)
                Button(L("evidence.save")) {
                    guard let start = from.value, let end = until.value else { return }
                    era.from = start
                    era.until = end
                    era.name = era.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.save(era: era)
                    done()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 520)
    }
}

/// Chooses the period something belongs to. The first choice is always the master, the whole timeline.
private struct EraChooser: View {
    let title: String
    let viewModel: any IEvidenceViewModel
    @Binding var selection: UUID?
    /// Periods that cannot be chosen.
    let excluding: Set<UUID>
    @State private var isOpen = false

    private var label: String {
        guard let selection, let era = viewModel.eras.first(where: { $0.id == selection }) else { return viewModel.masterTitle }
        return era.name
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Palette.ink)
            Button { isOpen.toggle() } label: {
                HStack(spacing: 6) {
                    Text(label).foregroundStyle(Palette.ink)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Palette.ink3)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                let nodes = viewModel.eraOutline.filter { !excluding.contains($0.id) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(nodes) { node in
                            Button {
                                selection = node.era?.id
                                isOpen = false
                            } label: {
                                HStack {
                                    Text(node.era?.name ?? viewModel.masterTitle)
                                        .foregroundStyle(Palette.ink).lineLimit(1)
                                    if let era = node.era {
                                        Text(era.dateLabel).font(.caption).foregroundStyle(Palette.ink3)
                                    }
                                    Spacer()
                                    if node.era?.id == selection { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                                }
                                .padding(.leading, 12 + CGFloat(node.depth) * 16).padding(.trailing, 12).padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(width: 380, height: min(320, CGFloat(nodes.count) * 36))
            }
        }
    }
}

/// Renames the master period, the one that covers the whole timeline.
private struct MasterForm: View {
    let viewModel: any IEvidenceViewModel
    @State private var name: String
    let done: () -> Void

    init(viewModel: any IEvidenceViewModel, done: @escaping () -> Void) {
        self.viewModel = viewModel
        self.done = done
        _name = State(initialValue: viewModel.masterTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("evidence.master.title")).font(.heading(.title3).weight(.semibold))
            Text(L("evidence.master.hint")).font(.caption).foregroundStyle(Palette.ink2)
            TextField(L("evidence.era.name"), text: $name)
            HStack {
                Spacer()
                Button(L("evidence.cancel"), role: .cancel, action: done).keyboardShortcut(.cancelAction)
                Button(L("evidence.save")) {
                    viewModel.setMasterName(name)
                    done()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 420)
    }
}

/// The timeline as a chart. The axis runs in whole years. The periods are bars on top, then each document has its
/// own row, with a point for every event on one date and a bar for every event that lasted for a period.
/// Pointing at the chart picks the nearest item.
private struct TimelineChart: View {
    let data: TimelineChartData
    @Binding var selected: UUID?
    @State private var hoveredDate: Date?
    @State private var hoveredLane: String?

    private var height: CGFloat { min(340, 64 + CGFloat(data.lanes.count) * 34) }

    private var names: [String: String] {
        Dictionary(data.lanes.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private var domain: ClosedRange<Date> {
        let years = data.years ?? 2000...2000
        return EvidenceDate(year: years.lowerBound).start...EvidenceDate(year: years.upperBound).end
    }

    private var picked: TimelineItem? { data.items.first { $0.id == selected } }

    private func pick() {
        guard let date = hoveredDate else { return }
        let inRow = data.items.filter { $0.lane == hoveredLane }
        // Without a row under the pointer the master, which covers everything, is not a candidate.
        let pool = inRow.isEmpty ? data.items.filter { $0.id != EraNode.masterID } : inRow
        func distance(_ item: TimelineItem) -> TimeInterval {
            let end = item.end ?? item.start
            if date < item.start { return item.start.timeIntervalSince(date) }
            if date > end { return date.timeIntervalSince(end) }
            return 0
        }
        if let nearest = pool.min(by: { distance($0) < distance($1) }) { selected = nearest.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(data.lanes.filter { !$0.isEra }) { lane in
                    RuleMark(y: .value("Row", lane.id))
                        .foregroundStyle(Palette.border)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                ForEach(data.items) { item in
                    if item.isEra {
                        BarMark(
                            xStart: .value("From", item.start), xEnd: .value("To", item.end ?? item.start),
                            y: .value("Row", item.lane), height: .fixed(18)
                        )
                        .foregroundStyle(Palette.accent.opacity(item.id == selected ? 0.6 : (item.depth == 0 ? 0.12 : min(0.5, 0.2 + 0.1 * Double(item.depth)))))
                        .cornerRadius(4)
                    } else if let end = item.end {
                        BarMark(
                            xStart: .value("From", item.start), xEnd: .value("To", end),
                            y: .value("Row", item.lane), height: .fixed(9)
                        )
                        .foregroundStyle(item.isGap ? Color.red : Palette.accent)
                        .opacity(item.id == selected ? 1 : 0.75)
                        .cornerRadius(3)
                    } else {
                        PointMark(x: .value("Date", item.start), y: .value("Row", item.lane))
                            .symbol(item.isGap ? .diamond : .circle)
                            .symbolSize(item.id == selected ? 170 : 80)
                            .foregroundStyle(item.isGap ? Color.red : Palette.accent)
                    }
                }
                if let picked {
                    RuleMark(x: .value("Date", picked.start))
                        .foregroundStyle(Palette.accent.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartYScale(domain: Array(data.lanes.map(\.id).reversed()))
            .chartXScale(domain: domain)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let id = value.as(String.self) {
                            Text(names[id] ?? "").font(.caption).foregroundStyle(Palette.ink2)
                                .lineLimit(1).truncationMode(.middle)
                                .frame(width: 170, alignment: .trailing)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .year)) { _ in
                    AxisGridLine().foregroundStyle(Palette.border.opacity(0.6))
                    AxisTick()
                    AxisValueLabel(format: .dateTime.year(), centered: true)
                }
            }
            .chartXSelection(value: $hoveredDate)
            .chartYSelection(value: $hoveredLane)
            .onChange(of: hoveredDate) { _, _ in pick() }
            .onChange(of: hoveredLane) { _, _ in pick() }
            .frame(height: height)
            Group {
                if let picked {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(picked.dateLabel).fontWeight(.semibold) + Text("  ·  ") + Text(picked.title)
                        ForEach(Array(picked.quotes.prefix(3).enumerated()), id: \.offset) { _, quote in
                            Text("“\(quote)”").font(.caption).foregroundStyle(Palette.accent).lineLimit(2)
                        }
                    }
                } else {
                    Text(L("evidence.timeline.pick")).foregroundStyle(Palette.ink3)
                }
            }
            .font(.callout)
            .foregroundStyle(Palette.ink)
            .lineLimit(2)
        }
    }
}

/// The places where the term appears in one PDF: the page and the words around it. A click opens the PDF there,
/// and the quote button starts a quote from the passage.
private struct OccurrencesList: View {
    let viewModel: any IEvidenceViewModel
    let row: EvidenceSourceRow
    let onQuote: (EvidenceQuote) -> Void
    /// Checked places are hidden so what is left is what still has to be read.
    @AppStorage("evidenceShowChecked") private var showChecked = false

    var body: some View {
        Group {
            if let scan = viewModel.occurrenceScan(of: row.id) {
                let checked = viewModel.checkedPlaces(of: row.id)
                let all = scan.places
                let checkedCount = all.filter { checked.contains($0.key) }.count
                let list = showChecked ? all : all.filter { !checked.contains($0.key) }
                let lead = viewModel.modifier.trimmingCharacters(in: .whitespacesAndNewlines)
                if all.isEmpty, scan.isDone {
                    Text(L("evidence.occurrences.none")).font(.caption).foregroundStyle(Palette.ink3)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if !all.isEmpty {
                                Text(Lf("evidence.occurrences.title", all.count)).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.ink2)
                                if !lead.isEmpty {
                                    Text("· " + Lf("evidence.occurrences.withCount", list.filter(\.withModifier).count, lead))
                                        .font(.subheadline).foregroundStyle(Palette.accent)
                                }
                            }
                            if checkedCount > 0 {
                                Spacer()
                                Button {
                                    showChecked.toggle()
                                } label: {
                                    Text(showChecked
                                         ? L("evidence.occurrences.hideChecked")
                                         : Lf("evidence.occurrences.showChecked", checkedCount))
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                            if !scan.isDone {
                                ProgressView().controlSize(.small)
                                Text(scan.pageCount > 0
                                     ? Lf("evidence.occurrences.progress", scan.pagesRead, scan.pageCount)
                                     : L("evidence.occurrences.loading"))
                                    .font(.caption).foregroundStyle(Palette.ink3)
                            }
                        }
                        if list.isEmpty, scan.isDone, checkedCount > 0 {
                            Text(L("evidence.occurrences.allChecked")).font(.caption).foregroundStyle(Palette.ink3)
                        }
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(list) { place in
                                let isChecked = checked.contains(place.key)
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Button { viewModel.openSource(id: row.id, page: place.page) } label: {
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
                                    if place.withModifier {
                                        Text(Lf("evidence.occurrences.withModifier", lead))
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Palette.accent)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Palette.accentLight, in: Capsule())
                                    }
                                    // A passage that is already a quote opens that quote instead of making a second one.
                                    let saved = viewModel.savedQuote(sourceID: row.id, text: place.quoteText, excluding: nil)
                                    Button {
                                        onQuote(saved ?? EvidenceQuote(
                                            text: place.quoteText,
                                            sourceID: row.id,
                                            locator: Lf("evidence.occurrences.page", place.page + 1)
                                        ))
                                    } label: {
                                        Image(systemName: saved == nil ? "quote.opening" : "quote.closing")
                                            .foregroundStyle(saved == nil ? Palette.ink2 : Palette.accent)
                                    }
                                    .buttonStyle(.borderless)
                                    .help(saved == nil ? L("evidence.occurrences.save") : L("evidence.occurrences.saved"))
                                    Button {
                                        viewModel.setChecked(!isChecked, key: place.key, sourceID: row.id)
                                    } label: {
                                        Image(systemName: isChecked ? "checkmark.circle.fill" : "checkmark.circle")
                                            .foregroundStyle(isChecked ? Palette.accent : Palette.ink3)
                                    }
                                    .buttonStyle(.borderless)
                                    .help(isChecked ? L("evidence.occurrences.uncheck") : L("evidence.occurrences.check"))
                                }
                                .opacity(isChecked ? 0.55 : 1)
                                .padding(.vertical, 6)
                                Divider()
                            }
                        }
                        if list.count >= 400 {
                            Text(Lf("evidence.occurrences.limit", list.count)).font(.caption2).foregroundStyle(Palette.ink3)
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L("evidence.occurrences.loading")).font(.caption).foregroundStyle(Palette.ink3)
                }
            }
        }
        // Starts at once, in step with the count: the places show up as the pages are read.
        .task(id: "\(viewModel.scanGeneration)|\(row.id)") { viewModel.loadOccurrences(of: row.id) }
    }

    /// The words around the term, with the term itself in bold.
    private func snippet(_ place: TermOccurrence) -> Text {
        Text("…" + place.before).foregroundColor(Palette.ink2)
            + Text(place.text).bold().foregroundColor(Palette.ink)
            + Text(place.after + "…").foregroundColor(Palette.ink2)
    }
}

/// Chooses the quote that shows an event, in a list in a popover.
private struct QuoteChooser: View {
    let title: String
    let viewModel: any IEvidenceViewModel
    @Binding var selection: UUID?
    @State private var isOpen = false

    private var label: String {
        guard let selection, let quote = viewModel.quotes.first(where: { $0.id == selection }) else { return "—" }
        return quote.text
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Palette.ink)
            Button { isOpen.toggle() } label: {
                HStack(spacing: 6) {
                    Text(label).foregroundStyle(Palette.ink)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Palette.ink3)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        choice("—", detail: nil, isChosen: selection == nil) { selection = nil }
                        ForEach(viewModel.quotes) { quote in
                            Divider()
                            choice(quote.text, detail: viewModel.sourceTitle(quote.sourceID), isChosen: quote.id == selection) {
                                selection = quote.id
                            }
                        }
                    }
                }
                .frame(width: 460, height: min(360, CGFloat(viewModel.quotes.count + 1) * 52))
            }
        }
    }

    private func choice(_ text: String, detail: String?, isChosen: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            isOpen = false
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text).foregroundStyle(Palette.ink).lineLimit(2).multilineTextAlignment(.leading)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(Palette.ink3).lineLimit(1)
                    }
                }
                Spacer()
                if isChosen { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Chooses the source of a quote or an event. It is drawn in SwiftUI (a button and a list in a popover), so the
/// title of the chosen source always shows.
private struct SourceMenu: View {
    let title: String
    let viewModel: any IEvidenceViewModel
    @Binding var selection: UUID?
    @State private var isOpen = false

    private var label: String {
        guard let selection else { return "—" }
        let name = viewModel.sourceTitle(selection)
        return name.isEmpty ? "—" : name
    }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Palette.ink)
            Button { isOpen.toggle() } label: {
                HStack(spacing: 6) {
                    Text(label)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Palette.ink3)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Palette.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        choice("—", isChosen: selection == nil) { selection = nil }
                        ForEach(viewModel.sourceOptions) { option in
                            Divider()
                            choice(option.title, isChosen: option.id == selection) { selection = option.id }
                        }
                    }
                }
                .frame(width: 420, height: min(320, CGFloat(viewModel.sourceOptions.count + 1) * 34))
            }
        }
    }

    private func choice(_ text: String, isChosen: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            isOpen = false
        } label: {
            HStack {
                Text(text).foregroundStyle(Palette.ink).lineLimit(2).multilineTextAlignment(.leading)
                Spacer()
                if isChosen { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
