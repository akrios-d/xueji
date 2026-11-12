import SwiftUI
import XuejiCore

/// The triage of a project: how often a term appears in the sources, the strongest quotes sorted by
/// importance, a timeline and the findings, ready to export.
struct TriageView: View {
    let viewModel: any ITriageViewModel

    private enum Tab: String, CaseIterable, Identifiable {
        case counts, quotes, timeline, findings, report
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .counts: return "number"
            case .quotes: return "quote.opening"
            case .timeline: return "calendar.day.timeline.left"
            case .findings: return "text.alignleft"
            case .report: return "doc.richtext"
            }
        }
    }

    @AppStorage("triageTab") private var tabName = Tab.counts.rawValue
    @State private var editingQuote: TriageQuote?
    @State private var editingEvent: TriageEvent?
    @State private var confirmingDelete = false

    private var tab: Tab { Tab(rawValue: tabName) ?? .counts }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch tab {
                case .counts: counts
                case .quotes: quotes
                case .timeline: timeline
                case .findings: findings
                case .report: report
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.bg)
        .navigationTitle(L("triage.title"))
        .navigationSubtitle(L("triage.subtitle"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { viewModel.copyReport() } label: {
                    Label(viewModel.justCopied ? L("compile.copied") : L("compile.copy"),
                          systemImage: viewModel.justCopied ? "checkmark" : "doc.on.clipboard")
                }
                .help(L("compile.copy"))
                Menu {
                    ForEach(TriageFormat.allCases) { format in
                        Button(L("triage.export." + format.rawValue)) { viewModel.export(format: format) }
                    }
                } label: {
                    Label(L("compile.export"), systemImage: "square.and.arrow.up")
                }
                .help(L("compile.export"))
            }
        }
        .sheet(item: $editingQuote) { quote in
            QuoteForm(viewModel: viewModel, quote: quote) { editingQuote = nil }
        }
        .sheet(item: $editingEvent) { event in
            EventForm(viewModel: viewModel, event: event) { editingEvent = nil }
        }
        .task { viewModel.refresh() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                triageMenu
                TextField(L("triage.titlePlaceholder"), text: Binding(
                    get: { viewModel.title }, set: { viewModel.setTitle($0) }
                ))
                .textFieldStyle(.plain)
                .font(.heading(.title3).weight(.bold))
            }
            Picker("", selection: $tabName) {
                ForEach(Tab.allCases) { tab in
                    Label(L("triage.tab." + tab.rawValue), systemImage: tab.symbol).tag(tab.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 620)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private var triageMenu: some View {
        Menu {
            ForEach(viewModel.triageList) { item in
                Button {
                    viewModel.selectTriage(id: item.id)
                } label: {
                    if item.isActive { Label(item.name, systemImage: "checkmark") } else { Text(item.name) }
                }
            }
            if !viewModel.triageList.isEmpty { Divider() }
            Button(L("triage.new")) { viewModel.addTriage() }
            Button(L("triage.deleteThis"), role: .destructive) { confirmingDelete = true }
                .disabled(viewModel.triageList.isEmpty)
        } label: {
            Label(L("triage.switch"), systemImage: "rectangle.stack")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L("triage.switch.help"))
        .confirmationDialog(L("triage.deleteThis.confirm"), isPresented: $confirmingDelete) {
            Button(L("triage.delete"), role: .destructive) { viewModel.deleteCurrentTriage() }
        }
    }

    // MARK: Counts

    private var counts: some View {
        let rows = viewModel.rows
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    labeled(L("triage.term")) {
                        TextField(L("triage.term.placeholder"), text: Binding(
                            get: { viewModel.term }, set: { viewModel.setTerm($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    labeled(L("triage.modifier")) {
                        TextField(L("triage.modifier.placeholder"), text: Binding(
                            get: { viewModel.modifier }, set: { viewModel.setModifier($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    if viewModel.isCounting { ProgressView().controlSize(.small) }
                }
                Text(L("triage.term.hint")).font(.caption).foregroundStyle(Palette.ink3)
                if rows.isEmpty {
                    Text(L("triage.noSources")).foregroundStyle(Palette.ink3).padding(.vertical, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            sourceRow(row)
                            Divider()
                        }
                    }
                    .background(Palette.surfaceAlt.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
                labeled(L("triage.corpusNote")) {
                    TextField(L("triage.corpusNote.placeholder"), text: Binding(
                        get: { viewModel.corpusNote }, set: { viewModel.setCorpusNote($0) }
                    ), axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                }
                labeled(L("triage.caution")) {
                    TextField(L("triage.caution.placeholder"), text: Binding(
                        get: { viewModel.caution }, set: { viewModel.setCaution($0) }
                    ), axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func sourceRow(_ row: TriageSourceRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { row.included && row.hasPDF }, set: { viewModel.setIncluded($0, sourceID: row.id) }
            ))
            .labelsHidden()
            .disabled(!row.hasPDF)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button { viewModel.openSource(id: row.id) } label: {
                        Text(row.title).font(.callout.weight(.medium)).foregroundStyle(Palette.ink).lineLimit(2)
                    }
                    .buttonStyle(.plain)
                    .disabled(!row.hasPDF || row.isFixed)
                    Spacer(minLength: 8)
                    countSummary(row)
                }
                HStack(spacing: 8) {
                    TextField(L("triage.date"), text: Binding(
                        get: { row.date }, set: { viewModel.setDate($0, sourceID: row.id) }
                    ))
                    .frame(width: 110)
                    TextField(L("triage.usage"), text: Binding(
                        get: { row.usage }, set: { viewModel.setUsage($0, sourceID: row.id) }
                    ))
                }
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .opacity(row.included && row.hasPDF ? 1 : 0.55)
        .contextMenu {
            if row.isFixed {
                Button(L("triage.row.remove"), role: .destructive) { viewModel.deleteDocument(id: row.id) }
            }
        }
    }

    @ViewBuilder
    private func countSummary(_ row: TriageSourceRow) -> some View {
        if !row.hasPDF {
            Text(L("triage.noPDF")).font(.caption).foregroundStyle(Palette.ink3)
        } else if !row.included {
            Text(L("triage.excluded")).font(.caption).foregroundStyle(Palette.ink3)
        } else if let count = row.count {
            if row.isFixed {
                Text(Lf("triage.countLine.imported", count.term, String(format: "%.2f", TermCounter.perThousand(count.term, words: count.words)), count.words))
                    .font(.caption.monospacedDigit()).foregroundStyle(Palette.ink2)
            } else if count.hasText {
                Text(Lf("triage.countLine", count.term, String(format: "%.2f", TermCounter.perThousand(count.term, words: count.words)), count.words))
                    .font(.caption.monospacedDigit()).foregroundStyle(Palette.ink2)
            } else {
                Label(L("triage.noText"), systemImage: "exclamationmark.triangle")
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
                Text(Lf("triage.quotes.count", quotes.count)).font(.subheadline).foregroundStyle(Palette.ink2)
                Spacer()
                Button { editingQuote = TriageQuote() } label: { Label(L("triage.quotes.add"), systemImage: "plus") }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            Divider()
            if quotes.isEmpty {
                emptyText(L("triage.quotes.empty"))
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

    private func quoteRow(_ quote: TriageQuote, number: Int, isFirst: Bool, isLast: Bool) -> some View {
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
            kindBadge(quote.kind)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editingQuote = quote }
        .contextMenu {
            Button(L("triage.edit")) { editingQuote = quote }
            Button(L("compile.moveUp")) { viewModel.moveQuote(id: quote.id, by: -1) }.disabled(isFirst)
            Button(L("compile.moveDown")) { viewModel.moveQuote(id: quote.id, by: 1) }.disabled(isLast)
            Divider()
            Button(L("triage.delete"), role: .destructive) { viewModel.deleteQuote(id: quote.id) }
        }
    }

    private func kindBadge(_ kind: TriageKind) -> some View {
        Text(L("triage.kind." + kind.rawValue))
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(kindColor(kind).opacity(0.18), in: Capsule())
            .foregroundStyle(kindColor(kind))
    }

    private func kindColor(_ kind: TriageKind) -> Color {
        switch kind {
        case .essential: return .green
        case .supporting: return .blue
        case .counter: return .orange
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        let events = viewModel.events
        return VStack(spacing: 0) {
            HStack {
                Text(Lf("triage.timeline.count", events.count)).font(.subheadline).foregroundStyle(Palette.ink2)
                Spacer()
                Button { editingEvent = TriageEvent() } label: { Label(L("triage.timeline.add"), systemImage: "plus") }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            Divider()
            if events.isEmpty {
                emptyText(L("triage.timeline.empty"))
            } else {
                List {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        eventRow(event, isFirst: index == 0, isLast: index == events.count - 1)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func eventRow(_ event: TriageEvent, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.date).font(.callout.weight(.semibold)).foregroundStyle(Palette.ink).frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.event).font(.callout).foregroundStyle(Palette.ink)
                if !event.who.isEmpty { Text(event.who).font(.caption).foregroundStyle(Palette.ink2) }
                if !event.frame.isEmpty { Text(event.frame).font(.caption).foregroundStyle(Palette.ink3).lineLimit(3) }
            }
            Spacer(minLength: 8)
            if event.isGap {
                Text(L("triage.gap")).font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.red.opacity(0.15), in: Capsule()).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editingEvent = event }
        .contextMenu {
            Button(L("triage.edit")) { editingEvent = event }
            Button(L("compile.moveUp")) { viewModel.moveEvent(id: event.id, by: -1) }.disabled(isFirst)
            Button(L("compile.moveDown")) { viewModel.moveEvent(id: event.id, by: 1) }.disabled(isLast)
            Divider()
            Button(L("triage.delete"), role: .destructive) { viewModel.deleteEvent(id: event.id) }
        }
    }

    // MARK: Findings

    private var findings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("triage.findings.hint")).font(.callout).foregroundStyle(Palette.ink2)
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

    @ViewBuilder
    private func reportBlock(_ block: ReportBlock) -> some View {
        switch block {
        case .title(let text):
            Text(text).font(.heading(.title).weight(.bold)).foregroundStyle(Palette.ink)
        case .subtitle(let text):
            Text(text).font(.caption).foregroundStyle(Palette.ink3)
        case .heading(let text):
            Text(text).font(.heading(.title3).weight(.semibold)).foregroundStyle(Palette.ink).padding(.top, 10)
        case .paragraph(let text):
            Text(text).font(.callout).foregroundStyle(Palette.ink2)
        case .callout(let text, _):
            Text(text).font(.callout).foregroundStyle(Palette.ink)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        case .table(let columns, let rows):
            reportTable(columns, rows)
        }
    }

    private func reportTable(_ columns: [ReportColumn], _ rows: [[ReportCell]]) -> some View {
        let total = CGFloat(max(columns.reduce(0) { $0 + $1.weight }, 1))
        let width: CGFloat = 1000
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
    let viewModel: any ITriageViewModel
    @State var quote: TriageQuote
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("triage.quote.title")).font(.heading(.title3).weight(.semibold))
            Text(L("triage.quote.text")).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
            TextEditor(text: $quote.text)
                .frame(height: 96)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
            Picker(L("triage.quote.source"), selection: $quote.sourceID) {
                Text("—").tag(UUID?.none)
                ForEach(viewModel.sourceOptions) { option in Text(option.title).tag(UUID?.some(option.id)) }
            }
            TextField(L("triage.quote.speaker"), text: $quote.speaker)
            TextField(L("triage.quote.locator"), text: $quote.locator)
            Picker(L("triage.col.class"), selection: $quote.kind) {
                ForEach(TriageKind.allCases) { kind in Text(L("triage.kind." + kind.rawValue)).tag(kind) }
            }
            .pickerStyle(.segmented)
            Text(L("triage.col.why")).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
            TextEditor(text: $quote.why)
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
            HStack {
                Spacer()
                Button(L("triage.cancel"), role: .cancel, action: done)
                    .keyboardShortcut(.cancelAction)
                Button(L("triage.save")) {
                    viewModel.save(quote: quote)
                    done()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(quote.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 520)
    }
}

private struct EventForm: View {
    let viewModel: any ITriageViewModel
    @State var event: TriageEvent
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("triage.event.title")).font(.heading(.title3).weight(.semibold))
            TextField(L("triage.col.date"), text: $event.date)
            TextField(L("triage.col.event"), text: $event.event)
            TextField(L("triage.col.who"), text: $event.who)
            Text(L("triage.col.frame")).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink2)
            TextEditor(text: $event.frame)
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
            Toggle(L("triage.event.gap"), isOn: $event.isGap)
            Picker(L("triage.event.source"), selection: $event.sourceID) {
                Text("—").tag(UUID?.none)
                ForEach(viewModel.sourceOptions) { option in Text(option.title).tag(UUID?.some(option.id)) }
            }
            .disabled(event.isGap)
            HStack {
                Spacer()
                Button(L("triage.cancel"), role: .cancel, action: done)
                    .keyboardShortcut(.cancelAction)
                Button(L("triage.save")) {
                    viewModel.save(event: event)
                    done()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(event.event.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && event.date.isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 520)
    }
}
