import SwiftUI

/// Prompts to paste into Claude, ChatGPT or any assistant, so that what it writes can be imported straight away.
struct PromptsView: View {
    let viewModel: any IPromptsViewModel
    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("prompts.intro")).font(.callout).foregroundStyle(.secondary)
                ForEach(viewModel.prompts) { prompt in card(prompt) }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(L("sidebar.prompts"))
    }

    private func card(_ prompt: PromptTemplate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(L("prompts.\(prompt.id).title"), systemImage: prompt.symbol).font(.headline)
                Spacer()
                Button {
                    viewModel.copy(prompt)
                } label: {
                    Label(
                        viewModel.copiedID == prompt.id ? L("prompts.copied") : L("prompts.copy"),
                        systemImage: viewModel.copiedID == prompt.id ? "checkmark" : "doc.on.doc"
                    )
                }
            }
            Text(L("prompts.\(prompt.id).use")).font(.callout)
            Label(L("prompts.\(prompt.id).where"), systemImage: "arrow.down.doc")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup(L("prompts.show"), isExpanded: Binding(
                get: { expanded.contains(prompt.id) },
                set: { if $0 { expanded.insert(prompt.id) } else { expanded.remove(prompt.id) } }
            )) {
                Text(prompt.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 6)
            }
            .font(.callout)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
