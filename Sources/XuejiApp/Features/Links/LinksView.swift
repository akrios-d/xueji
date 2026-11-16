import SwiftUI
import XuejiCore

/// Paste a reference list: the online ones become tasks that are done once their link opens.
struct LinksView: View {
    let viewModel: any ILinksViewModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("converter.input")).font(.headline)
                TextEditor(text: Binding(get: { viewModel.input }, set: { viewModel.setInput($0) }))
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                Text(L("links.hint")).font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 320, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 8) {
                if !viewModel.isOnline {
                    Label(L("network.offline.links"), systemImage: "wifi.slash")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    Button(L("links.check")) { viewModel.check() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.isOnline || viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isChecking)
                    Button(L("links.recheck")) { viewModel.recheckOpen() }
                        .disabled(!viewModel.isOnline || viewModel.isChecking || viewModel.tasks.allSatisfy(\.isDone))
                    if viewModel.isChecking { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(L("converter.clear")) { viewModel.clear() }
                        .disabled(viewModel.input.isEmpty && viewModel.tasks.isEmpty)
                }
                if !viewModel.tasks.isEmpty {
                    Text(Lf("links.summary", viewModel.doneCount, viewModel.tasks.count)).font(.subheadline)
                    if viewModel.offlineCount > 0 {
                        Text(Lf("links.offline", viewModel.offlineCount)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if viewModel.tasks.isEmpty {
                    ContentUnavailableView(L("links.empty"), systemImage: "link")
                } else {
                    List(viewModel.tasks) { task in row(task) }
                }
            }
            .padding()
            .frame(minWidth: 380, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ task: LinkTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            icon(task).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.text).lineLimit(3).textSelection(.enabled)
                    .strikethrough(task.isDone, color: .secondary)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(task.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let reason = reason(task) { Text(reason).font(.caption).foregroundStyle(color(task)) }
            }
            VStack(spacing: 6) {
                Button { viewModel.openLink(task.id) } label: { Image(systemName: "arrow.up.right.square") }
                    .help(L("finder.open"))
                if !task.status.isDone {
                    Button { viewModel.toggleConfirmed(task.id) } label: {
                        Image(systemName: task.confirmedByHand ? "arrow.uturn.backward.circle" : "checkmark.circle")
                    }
                    .help(L(task.confirmedByHand ? "links.markTodo" : "links.markDone"))
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func icon(_ task: LinkTask) -> some View {
        if task.status == .checking {
            ProgressView().controlSize(.small)
        } else if task.isDone {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            switch task.status {
            case .blocked: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .broken, .unreachable: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            default: Image(systemName: "circle").foregroundStyle(.secondary)
            }
        }
    }

    private func color(_ task: LinkTask) -> Color {
        switch task.status {
        case .blocked: return .orange
        case .broken, .unreachable: return .red
        default: return .secondary
        }
    }

    private func reason(_ task: LinkTask) -> String? {
        if task.confirmedByHand && !task.status.isDone { return L("links.status.hand") }
        switch task.status {
        case .ok(let code): return Lf("links.status.ok", code)
        case .blocked(let code): return Lf("links.status.blocked", code)
        case .broken(let code): return Lf("links.status.broken", code)
        case .unreachable: return L("links.status.unreachable")
        case .pending, .checking: return nil
        }
    }
}
