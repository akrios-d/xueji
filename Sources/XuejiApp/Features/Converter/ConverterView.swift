import SwiftUI
import XuejiCore

/// Paste a reference list in any supported style and get it back in another.
struct ConverterView: View {
    let viewModel: any IConverterViewModel

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("converter.input")).font(.headline)
                TextEditor(text: Binding(get: { viewModel.input }, set: { viewModel.setInput($0) }))
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                Text(L("converter.hint")).font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 320, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker(L("converter.target"), selection: Binding(
                        get: { viewModel.targetStyle }, set: { viewModel.setTargetStyle($0) }
                    )) {
                        ForEach(CitationStyle.allCases) { style in Text(L("compile.style." + style.rawValue)).tag(style) }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                    Button(L("converter.copyAll")) { viewModel.copyAll() }
                        .disabled(viewModel.results.isEmpty)
                    Button(L("converter.clear")) { viewModel.clear() }
                        .disabled(viewModel.input.isEmpty)
                }
                if viewModel.results.isEmpty {
                    ContentUnavailableView(L("converter.empty"), systemImage: "arrow.left.arrow.right")
                } else {
                    List(viewModel.results) { result in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.text)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if !result.missing.isEmpty {
                                    Label(
                                        Lf("converter.missing", result.missing.map { L("converter.field." + $0) }.joined(separator: ", ")),
                                        systemImage: "exclamationmark.triangle"
                                    )
                                    .font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Button { viewModel.copy(result) } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.borderless)
                                .help(L("converter.copy"))
                        }
                        .padding(.vertical, 4)
                        .contextMenu { Button(L("converter.copy")) { viewModel.copy(result) } }
                    }
                }
            }
            .padding()
            .frame(minWidth: 360, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
