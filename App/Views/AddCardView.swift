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
                                    tile(name: template.name, colorHex: template.colorHex, symbol: nil,
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

    private func tile(name: String, colorHex: String, symbol: String?, domain: String? = nil) -> some View {
        let ink = Color.onCard(colorHex)
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color.shade(colorHex, by: 0.12), Color(hex: colorHex), Color.shade(colorHex, by: -0.2)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let domain {
                StoreLogoView(domain: domain, height: 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            if let symbol {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(name)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(ink)
                .lineLimit(2)
                .padding(12)
        }
        .aspectRatio(Brand.cardAspect, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
        }
        .contentShape(Rectangle())
    }
}
