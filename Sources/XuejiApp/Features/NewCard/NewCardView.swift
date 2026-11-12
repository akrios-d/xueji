import SwiftUI
import XuejiCore

/// The form that creates a card: pick what it is, give it a title, and a link when it has one.
/// Sources also ask how important they are (essential, complementary, secondary) and who wrote them.
struct NewCardView: View {
    let viewModel: any INewCardViewModel
    @State private var input = NewCardInput()
    @State private var showsMore = false
    @FocusState private var isTitleFocused: Bool

    private static let classifications: [Classification] = [.essential, .complementary, .secondary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("card.new")).font(.heading(.headline)).foregroundStyle(Palette.ink)

            Picker(L("card.type"), selection: typeBinding) {
                ForEach(viewModel.types) { type in
                    Label(type.name, systemImage: type.symbol).tag(type.id)
                }
            }
            .pickerStyle(.menu)

            TextField(L("card.title.placeholder"), text: $input.title)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
                .onSubmit(create)

            TextField(viewModel.requiresLink ? L("card.link.required") : L("card.link.optional"), text: $input.link)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            if viewModel.isSource { sourceDetails }

            HStack {
                Spacer()
                Button(L("card.create"), action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canCreate(input))
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear {
            input = NewCardInput()
            showsMore = false
            isTitleFocused = true
        }
    }

    private var sourceDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L("panel.classification"), selection: $input.classification) {
                Text(L("panel.none")).tag(Classification?.none)
                Divider()
                ForEach(Self.classifications, id: \.self) { classification in
                    Text(classification.title).tag(Classification?.some(classification))
                }
            }
            .pickerStyle(.menu)
            if let classification = input.classification {
                Text(classification.summary)
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField(L("card.authors.placeholder"), text: $input.authors)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                TextField(L("card.year.placeholder"), text: $input.year)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Picker(L("card.kind"), selection: $input.kind) {
                    Text(L("panel.none")).tag("")
                    Divider()
                    ForEach(viewModel.kinds) { kind in Text(kind.label).tag(kind.id) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            DisclosureGroup(L("card.more"), isExpanded: $showsMore) {
                VStack(spacing: 8) {
                    TextField(L("card.venue.placeholder"), text: $input.venue)
                        .textFieldStyle(.roundedBorder)
                    TextField(L("card.doi.placeholder"), text: $input.doi)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.top, 6)
            }
            .font(.callout)
        }
    }

    private var typeBinding: Binding<UUID> {
        Binding(get: { viewModel.selectedTypeID }, set: { viewModel.selectType($0) })
    }

    private func create() {
        guard viewModel.canCreate(input) else { return }
        viewModel.create(input)
    }
}
