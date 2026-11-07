import SwiftUI

/// Step 1 of adding a card: pick the store (or another one), then the editor opens with the scanner.
struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var path: [Choice] = []
    @State private var showScan = false
    /// A card scanned whose store wasn't recognised: picking a store fills in its number.
    @State private var scanned: ScannedCode?

    struct ScannedCode: Equatable {
        var number: String
        var format: BarcodeFormat
    }

    enum Choice: Hashable {
        case template(StoreTemplate)
        case custom(String)
    }

    private var templates: [StoreTemplate] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let list = StoreTemplates.all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
                scanBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
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
                    CardEditorView(template: template, number: scanned?.number, format: scanned?.format, onSaved: { dismiss() })
                case .custom(let name):
                    CardEditorView(storeName: name, number: scanned?.number, format: scanned?.format, onSaved: { dismiss() })
                }
            }
        }
        .fullScreenCover(isPresented: $showScan) {
            CardScanView(onAdded: { _ in dismiss() },
                         onUnknownStore: { number, format in
                             withAnimation { scanned = ScannedCode(number: number, format: format) }
                         })
        }
    }

    /// "Scan je kaart" at the top; after a scan with an unknown store: which store is it?
    @ViewBuilder private var scanBanner: some View {
        if let scanned {
            HStack(spacing: 12) {
                Image(systemName: "barcode").font(.title2).foregroundStyle(Brand.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kaart gescand").font(.headline)
                    Text("Welke winkel is \(scanned.number)? Kies hem hieronder.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { withAnimation { self.scanned = nil } } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else if ScannerView.isAvailable {   // geen camera-scanner op de Mac of Vision Pro
            Button { showScan = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 26, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan je kaart").font(.headline)
                        Text("Pasr herkent de winkel en zet hem er meteen in").font(.subheadline).opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(LinearGradient(colors: [Brand.iris, Brand.iris.opacity(0.7)], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
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
