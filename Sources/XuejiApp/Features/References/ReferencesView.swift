import SwiftUI

/// The three reference tools in one place: find a work, convert a list to another style, check the links of a list.
struct ReferencesView: View {
    let finder: any IFinderViewModel
    let converter: any IConverterViewModel
    let links: any ILinksViewModel

    enum Tab: String, CaseIterable, Identifiable {
        case find, convert, links
        var id: String { rawValue }
        var title: String { L("references.tab." + rawValue) }
    }

    /// Also set by the menu commands (⌘9, ⌘0, ⌥⌘1) before they open this screen.
    @AppStorage("referencesTab") private var tabName = Tab.find.rawValue

    private var tab: Binding<Tab> {
        Binding(get: { Tab(rawValue: tabName) ?? .find }, set: { tabName = $0.rawValue })
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: tab) {
                ForEach(Tab.allCases) { tab in Text(tab.title).tag(tab) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.top, 12)
            .padding(.bottom, 4)
            Group {
                switch tab.wrappedValue {
                case .find: FinderView(viewModel: finder)
                case .convert: ConverterView(viewModel: converter)
                case .links: LinksView(viewModel: links)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle(L("sidebar.references"))
    }
}
