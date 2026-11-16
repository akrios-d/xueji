import SwiftUI
import XuejiCore

struct ProgressOverviewView: View {
    let viewModel: any IProgressViewModel
    /// Ids of the open blocks. The first three start open; deadlines, decisions and writing start folded.
    @AppStorage("progressOpenBlocks") private var openRaw = "period,perWeek,stages"

    var body: some View {
        let stats = viewModel.stats
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if viewModel.hasNoHistory {
                    Text(L("progress.noHistory"))
                        .font(.callout).foregroundStyle(Palette.ink2)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surfaceAlt, in: RoundedRectangle(cornerRadius: Radius.md))
                }
                periodSection
                finishedPerWeek(stats)
                stages(stats)
                deadlines(stats)
                decisions(stats)
                writing
            }
            .padding(Space.lg)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.bg)
        .navigationTitle(L("progress.title"))
        .navigationSubtitle(L("progress.subtitle"))
    }

    // MARK: Sections

    private var periodSection: some View {
        let mine = viewModel.periodTotals
        let other = viewModel.comparisonTotals
        let comparing = viewModel.isComparing
        return block("period", L("progress.period")) {
            VStack(alignment: .leading, spacing: 8) {
                periodPicker(L("progress.period.label"), slot: .primary, period: viewModel.period, range: viewModel.periodRange)
                Toggle(L("progress.compare"), isOn: Binding(get: { viewModel.isComparing }, set: { viewModel.setComparing($0) }))
                    .toggleStyle(.checkbox)
                if comparing {
                    periodPicker(L("progress.compareWith"), slot: .comparison, period: viewModel.comparisonPeriod, range: viewModel.comparisonRange)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                metric(L("progress.finished"), mine.finished, comparing ? other.finished : nil, "checkmark.circle", .up)
                metric(L("progress.sourcesRead"), mine.sourcesFinished, comparing ? other.sourcesFinished : nil, "books.vertical", .up)
                metric(L("progress.started"), mine.created, comparing ? other.created : nil, "plus.circle", .up)
                metric(L("progress.approved"), mine.approved, comparing ? other.approved : nil, "hand.thumbsup", .up)
                metric(L("progress.rejected"), mine.rejected, comparing ? other.rejected : nil, "hand.thumbsdown", .neutral)
                metric(L("progress.onTime"), mine.finishedOnTime, comparing ? other.finishedOnTime : nil, "checkmark.seal", .up)
                metric(L("progress.late"), mine.finishedLate, comparing ? other.finishedLate : nil, "clock.badge.exclamationmark", .down)
            }
            Text(L("progress.deadlines.hint")).font(.caption).foregroundStyle(Palette.ink3)
        }
    }

    private func periodPicker(_ title: String, slot: ProgressSlot, period: ProgressPeriod, range: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2)
                Picker("", selection: Binding(get: { period.preset }, set: { viewModel.setPreset($0, for: slot) })) {
                    ForEach(ProgressPreset.allCases.filter { slot == .comparison || $0 != .previous }, id: \.self) { preset in
                        Text(L("progress.preset." + preset.rawValue)).tag(preset)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Text(rangeText(range, preset: period.preset)).font(.caption).foregroundStyle(Palette.ink3)
            }
            if period.preset == .custom {
                HStack(spacing: 10) {
                    DatePicker(L("progress.from"), selection: Binding(
                        get: { period.from }, set: { viewModel.setCustom(from: $0, to: period.to, for: slot) }
                    ), displayedComponents: .date)
                    DatePicker(L("progress.to"), selection: Binding(
                        get: { period.to }, set: { viewModel.setCustom(from: period.from, to: $0, for: slot) }
                    ), displayedComponents: .date)
                }
                .datePickerStyle(.compact).fixedSize()
            }
        }
    }

    private func rangeText(_ range: DateInterval, preset: ProgressPreset) -> String {
        if preset == .allTime { return "" }
        let last = range.end.addingTimeInterval(-1)
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Localization.locale)
        return "\(range.start.formatted(style)) – \(last.formatted(style))"
    }

    private enum Good { case up, down, neutral }

    /// A number for the period, and, when comparing, what it was in the other period and the change.
    private func metric(_ title: String, _ value: Int, _ before: Int?, _ symbol: String, _ good: Good) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Palette.accent)
            Text("\(value)").font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.ink)
            Text(title).font(.caption).foregroundStyle(Palette.ink2).lineLimit(2)
            if let before {
                let change = value - before
                HStack(spacing: 6) {
                    Text(change == 0 ? "=" : (change > 0 ? "+\(change)" : "\(change)"))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(changeColor(change, good))
                    Text(Lf("progress.before", before)).font(.caption).foregroundStyle(Palette.ink3)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.border))
    }

    private func changeColor(_ change: Int, _ good: Good) -> Color {
        if change == 0 || good == .neutral { return Palette.ink3 }
        let better = (good == .up) == (change > 0)
        return better ? Palette.accent : Palette.neg
    }

    private func finishedPerWeek(_ stats: ProgressStats) -> some View {
        block("perWeek", L("progress.perWeek")) {
            Bars(items: stats.weeks.map { Bar(id: $0.start, label: weekLabel($0.start), parts: [.init(value: $0.finished, color: Palette.accent)]) })
            Text(Lf("progress.totalFinished", stats.totalFinished)).font(.caption).foregroundStyle(Palette.ink3)
        }
    }

    private func stages(_ stats: ProgressStats) -> some View {
        block("stages", L("progress.stages")) {
            HStack(spacing: 12) {
                ForEach(Stage.allCases, id: \.self) { stage in
                    tile(stage.title, "\(stats.stageCounts[stage] ?? 0)", symbol: stage.symbol)
                }
            }
        }
    }

    private func deadlines(_ stats: ProgressStats) -> some View {
        block("deadlines", L("progress.deadlinesNow")) {
            HStack(spacing: 12) {
                tile(L("progress.overdue"), "\(stats.overdue)", symbol: "exclamationmark.circle", tint: stats.overdue > 0 ? Palette.neg : nil)
                tile(L("progress.dueThisWeek"), "\(stats.dueThisWeek)", symbol: "calendar")
            }
        }
    }

    private func decisions(_ stats: ProgressStats) -> some View {
        let mine = viewModel.periodTotals
        let other = viewModel.comparisonTotals
        let comparing = viewModel.isComparing
        return block("decisions", L("progress.decisions")) {
            Text(L("progress.decisions.period")).font(.caption).foregroundStyle(Palette.ink3)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                metric(L("progress.approvedOwn"), mine.approvedOwn, comparing ? other.approvedOwn : nil, "hand.thumbsup", .neutral)
                metric(L("progress.approvedAgents"), mine.approvedByAgents, comparing ? other.approvedByAgents : nil, "sparkles", .neutral)
                metric(L("progress.rejectedOwn"), mine.rejectedOwn, comparing ? other.rejectedOwn : nil, "hand.thumbsdown", .neutral)
                metric(L("progress.rejectedAgents"), mine.rejectedByAgents, comparing ? other.rejectedByAgents : nil, "xmark.circle", .neutral)
            }
            if let last = stats.lastDecisionAt {
                Text(Lf("progress.lastDecision", relative(last))).font(.caption).foregroundStyle(Palette.ink3)
            }
            Text(L("progress.decisionsPerWeek")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2).padding(.top, 4)
            Bars(items: stats.weeks.map {
                Bar(id: $0.start, label: weekLabel($0.start), parts: [
                    .init(value: $0.approved, color: Palette.accent), .init(value: $0.rejected, color: Palette.neg),
                ])
            })
            HStack(spacing: 14) {
                legend(Palette.accent, L("progress.approved"))
                legend(Palette.neg, L("progress.rejected"))
            }
            if !mine.decisions.isEmpty {
                Text(L("progress.recent")).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2).padding(.top, 4)
                VStack(spacing: 0) {
                    ForEach(mine.decisions.prefix(15)) { decision in
                        HStack(spacing: 10) {
                            Image(systemName: decision.approved ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(decision.approved ? Palette.accent : Palette.neg)
                            Text(decision.title).lineLimit(1).foregroundStyle(Palette.ink)
                            if decision.proposedByAgent {
                                Image(systemName: "sparkles").font(.caption).foregroundStyle(Palette.ink3)
                                    .help(L("progress.byAgent"))
                            }
                            Spacer()
                            Text(decision.at.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Localization.locale)))
                                .font(.caption.monospacedDigit()).foregroundStyle(Palette.ink3)
                        }
                        .padding(.vertical, 7)
                        Divider()
                    }
                }
            }
        }
    }

    private var writing: some View {
        block("writing", L("progress.writing")) {
            HStack(spacing: 12) {
                tile(L("progress.words"), "\(viewModel.totalWords)", symbol: "text.alignleft")
                tile(L("progress.drafts"), "\(viewModel.draftRows.count)", symbol: "square.and.pencil")
            }
            ForEach(viewModel.draftRows.prefix(6)) { row in
                Button { viewModel.openDraft(id: row.id) } label: {
                    HStack {
                        Text(row.title).lineLimit(1).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(Lf("compile.words", row.words)).font(.caption.monospacedDigit()).foregroundStyle(Palette.ink3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
            Text(L("progress.writing.hint")).font(.caption).foregroundStyle(Palette.ink3)
        }
    }

    // MARK: Pieces

    /// A block with a title that folds. The secondary ones start folded; the choice is remembered.
    private func block<Content: View>(_ id: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        let isOpen = openBlocks.contains(id)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    var set = openBlocks
                    if isOpen { set.remove(id) } else { set.insert(id) }
                    openRaw = set.sorted().joined(separator: ",")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(Palette.ink3)
                    Text(title).font(.sectionTitle).foregroundStyle(Palette.ink)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen { content() }
        }
    }

    private var openBlocks: Set<String> {
        Set(openRaw.split(separator: ",").map(String.init))
    }

    private func tile(_ title: String, _ value: String, symbol: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint ?? Palette.accent)
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint ?? Palette.ink)
            Text(title).font(.caption).foregroundStyle(Palette.ink2).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.border))
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption).foregroundStyle(Palette.ink3)
        }
    }

    private func weekLabel(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.defaultDigits).locale(Localization.locale))
    }

    private func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(Localization.locale))
    }
}

// MARK: - Bars

private struct Bar: Identifiable {
    struct Part { let value: Int; let color: Color }
    let id: Date
    let label: String
    let parts: [Part]
    var total: Int { parts.reduce(0) { $0 + $1.value } }
}

/// A small column chart, one column per week, stacked when a week has several kinds.
private struct Bars: View {
    let items: [Bar]
    private let height: CGFloat = 90

    var body: some View {
        let peak = max(items.map(\.total).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(items) { item in
                VStack(spacing: 4) {
                    Text(item.total > 0 ? "\(item.total)" : " ").font(.caption2.monospacedDigit()).foregroundStyle(Palette.ink3)
                    VStack(spacing: 1) {
                        Spacer(minLength: 0)
                        ForEach(Array(item.parts.enumerated()), id: \.offset) { _, part in
                            if part.value > 0 {
                                RoundedRectangle(cornerRadius: 3).fill(part.color)
                                    .frame(height: max(4, height * CGFloat(part.value) / CGFloat(peak)))
                            }
                        }
                    }
                    .frame(height: height)
                    Text(item.label).font(.caption2).foregroundStyle(Palette.ink3).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
