import SwiftUI

/// Step 1 of adding a card: pick the store (or another one), then the editor opens with the scanner.
struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var path: [Choice] = []

    enum Choice: Hashable {
        case template(StoreTemplate)
        case custom(String)
    }

    private var templates: [StoreTemplate] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let list = StoreTemplates.all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !query.isEmpty else { return list }
        return list.filter { t in t.matchTerms.contains { $0.localizedCaseInsensitiveContains(query) } }
    }

    /// By category; while searching, one list without headers.
    private var groups: [(String, [StoreTemplate])] {
        let list = templates
        guard search.trimmingCharacters(in: .whitespaces).isEmpty else { return [("", list)] }
        return StoreTemplates.categories.map { category in (category, list.filter { $0.category == category }) }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12, pinnedViews: [.sectionHeaders]) {
                    Button { path.append(.custom(search)) } label: {
                        tile(name: search.isEmpty ? String(localized: "Andere winkel") : search,
                             colorHex: "#2B2F3A", symbol: "plus")
                    }
                    .buttonStyle(.plain)

                    ForEach(groups, id: \.0) { category, items in
                        Section {
                            ForEach(items) { template in
                                Button { path.append(.template(template)) } label: {
                                    tile(name: template.name, colorHex: template.cardHex, symbol: nil,
                                         domain: template.domain.isEmpty ? nil : template.domain)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            if !category.isEmpty {
                                Text(category)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .background(Brand.ink)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Kaart toevoegen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $search, prompt: Text("Naam van de winkel"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
            }
            .navigationDestination(for: Choice.self) { choice in
                switch choice {
                case .template(let template):
                    CardEditorView(template: template, onSaved: { dismiss() })
                case .custom(let name):
                    CardEditorView(storeName: name, onSaved: { dismiss() })
                }
            }
        }
    }

    /// A tile like the cards in SuperCards: the brand colour with the logo big in the middle, the name
    /// underneath. Without a logo, the name goes on the tile.
    private func tile(name: String, colorHex: String, symbol: String?, domain: String? = nil) -> some View {
        let ink = Color.onCard(colorHex)
        let hasLogo = domain.map { LogoService.bundledLogo(for: $0) != nil } ?? false
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                shape.fill(Color(hex: colorHex))
                if let domain {
                    // Like SuperCards: the logo big in the middle of the brand colour.
                    GeometryReader { geo in
                        StoreLogoView(domain: domain, height: geo.size.height * 0.46, maxWidth: geo.size.width * 0.66)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if let symbol {
                    Image(systemName: symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if !hasLogo && symbol == nil {
                    Text(name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .padding(12)
                }
            }
            .aspectRatio(Brand.cardAspect, contentMode: .fit)
            .clipShape(shape)
            Text(name)
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }
}
