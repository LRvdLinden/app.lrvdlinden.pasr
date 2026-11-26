import SwiftUI

/// Step 1 of adding a card: pick the store (or another one), then the editor opens with the scanner.
struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var path: [Choice]
    @State private var requesting = false
    /// Wat je toevoegt: een klantenkaart, een cadeaukaart/voucher of een stempelkaart van een zaak. De lijst toont
    /// alleen die soort; bij Stempelkaart de lijst van zaken (pasr_business_directory).
    @State private var kind: CardKind
    @State private var pickedStampCard: IncomingBusinessCard?
    private var catalog = StoreCatalog.shared

    /// `store`: meteen naar die winkel (bijvoorbeeld vanuit de melding "nieuwe winkel").
    init(store: StoreTemplate? = nil) {
        _path = State(initialValue: store.map { [Choice.template($0)] } ?? [])
        _kind = State(initialValue: store?.kind ?? .loyalty)
    }
    @State private var showScan = false
    /// A card scanned whose store wasn't recognised: picking a store fills in its number.
    @State private var scanned: ScannedCode?

    struct ScannedCode: Equatable {
        var number: String
        var format: BarcodeFormat
    }

    enum Choice: Hashable {
        case template(StoreTemplate)
        case custom(String, CardKind)
    }

    /// Onderaan (en als zoeken niets oplevert): een winkel aanvragen.
    private var missingStore: some View {
        Button { requesting = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "storefront")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(search.isEmpty ? "Mis je een winkel?" : "\(search) staat er niet tussen?").font(.headline)
                    Text("Ook cadeaukaarten en vouchers. Is hij toegevoegd, dan krijg je een melding.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func templates(of kind: CardKind) -> [StoreTemplate] {
        _ = catalog.version   // opnieuw tekenen als er winkels bij zijn gekomen
        let query = search.trimmingCharacters(in: .whitespaces)
        let list = StoreTemplates.all.filter { $0.kind == kind }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !query.isEmpty else { return list }
        return list.filter { t in t.matchTerms.contains { $0.localizedCaseInsensitiveContains(query) } }
    }

    private var templates: [StoreTemplate] { templates(of: kind) }

    /// Bij zoeken: staat de winkel er ook als de andere soort in? Dan wijzen we erop.
    private var otherKindMatch: StoreTemplate? {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return templates(of: kind == .voucher ? .loyalty : .voucher).first
    }

    /// By category (empty ones left out); while searching, one list without headers.
    private var groups: [(String, [StoreTemplate])] {
        let list = templates
        guard search.trimmingCharacters(in: .whitespaces).isEmpty else { return list.isEmpty ? [] : [("", list)] }
        let known = Set(StoreTemplates.categories)
        let rest = list.filter { !known.contains($0.category) }
        return (StoreTemplates.categories.map { category in (category, list.filter { $0.category == category }) }
                + [(String(localized: "Overig"), rest)])
            .filter { !$0.1.isEmpty }
    }

    private var kindPicker: some View {
        Picker("Soort kaart", selection: $kind.animation(.snappy)) {
            Label("Klantenkaart", systemImage: "creditcard").tag(CardKind.loyalty)
            Label("Cadeaukaart", systemImage: "gift").tag(CardKind.voucher)
            Label("Stempelkaart", systemImage: CardKind.stamps.symbol).tag(CardKind.stamps)
            Label("Ticket", systemImage: CardKind.ticket.symbol).tag(CardKind.ticket)
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleAndIcon)
    }

    /// Onder de keuze: kortingscode, ticket en abonnement voeg je zelf toe (een stempelkaart komt alleen van een zaak) (ze staan niet in de
    /// winkellijst). Twee per rij, zodat ze ook op een smalle iPhone (of het buitenscherm van een iPhone Duo) passen.
    private var otherKinds: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(CardKind.others.filter { kind != .ticket || $0 != .ticket }) { other in
                Button {
                    if other == .ticket { kind = .ticket } else { path.append(.custom(search, other)) }
                } label: {
                    Label(other.displayName, systemImage: other.symbol)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Nieuwe \(other.displayName.lowercased()) toevoegen"))
            }
        }
    }

    /// Tijdens zoeken: "Kruidvat heeft ook een cadeaukaart. Toon cadeaukaart".
    @ViewBuilder private var otherKindHint: some View {
        if let other = otherKindMatch {
            let isVoucher = other.kind == .voucher
            Button {
                withAnimation(.snappy) { kind = other.kind }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isVoucher ? "gift" : "creditcard")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                    (Text(isVoucher ? "Er is ook een cadeaukaart. " : "Er is ook een klantenkaart. ")
                     + Text(isVoucher ? "Toon cadeaukaarten" : "Toon klantenkaarten").foregroundStyle(Brand.mint).bold())
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                kindPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                if kind == .stamps {
                    scanBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    StampDirectoryView(search: search) { id in pickedStampCard = IncomingBusinessCard(cardID: id) }
                        .padding(16)
                        .padding(.bottom, 12)
                } else {
                otherKinds
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                scanBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                otherKindHint
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                LazyVGrid(columns: columns, spacing: 12, pinnedViews: [.sectionHeaders]) {
                    Button { path.append(.custom(search, kind)) } label: {
                        tile(name: search.isEmpty ? String(localized: kind == .ticket ? "Ander ticket" : kind == .voucher ? "Andere cadeaukaart" : "Andere winkel") : search,
                             colorHex: "#2B2F3A", symbol: "plus")
                    }
                    .buttonStyle(.plain)

                    ForEach(groups, id: \.0) { category, items in
                        Section {
                            ForEach(items) { template in
                                Button { path.append(.template(template)) } label: {
                                    tile(name: template.name, colorHex: template.cardHex, symbol: nil,
                                         domain: template.domain.isEmpty ? nil : template.domain,
                                         balanceCheck: template.kind == .voucher && BalancePages.url(for: template.id) != nil,
                                         cover: template.kind == .voucher ? RemoteStores.cover(for: template.id) : nil)
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

                missingStore
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Kaart toevoegen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $search, prompt: kind == .stamps ? Text("Zaak of plaats") : kind == .ticket ? Text("Naam van het evenement") : Text("Naam van de winkel"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer", systemImage: "xmark") { dismiss() } }
            }
            .navigationDestination(for: Choice.self) { choice in
                switch choice {
                case .template(let template):
                    CardEditorView(template: template, number: scanned?.number, format: scanned?.format, onSaved: { dismiss() })
                case .custom(let name, let kind):
                    CardEditorView(storeName: name, kind: kind, number: scanned?.number, format: scanned?.format, onSaved: { dismiss() })
                }
            }
        }
        .sheet(isPresented: $requesting) { StoreRequestSheet(name: search) }
        .sheet(item: $pickedStampCard) { item in
            JoinBusinessSheet(cardID: item.cardID, onDone: { dismiss() })
        }
        .task { await catalog.refresh() }
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
                        Text(kind == .voucher ? "Scan je cadeaukaart" : kind == .stamps ? "Scan de QR-code bij de zaak" : "Scan je kaart").font(.headline)
                        Text(kind == .voucher ? "Met saldo, vervaldatum en saldo-checker"
                             : kind == .stamps ? "Van de toonbank of de flyer: zo meld je je aan"
                             : "Pasr herkent de winkel en zet hem er meteen in")
                            .font(.subheadline).opacity(0.85)
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
    private func tile(name: String, colorHex: String, symbol: String?, domain: String? = nil,
                      balanceCheck: Bool = false, cover: Data? = nil) -> some View {
        let ink = Color.onCard(colorHex)
        // Cadeaukaart met een kaartontwerp uit het beheer: de echte kaart als tegel.
        let coverImage = cover.flatMap { Image(data: $0) }
        let hasLogo = domain.map { LogoService.bundledLogo(for: $0) != nil } ?? false
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                shape.fill(Color(hex: colorHex))
                if let coverImage {
                    coverImage.resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .accessibilityHidden(true)
                } else if let domain {
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
                if !hasLogo && symbol == nil && coverImage == nil {
                    Text(name)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .padding(12)
                }
            }
            .overlay(alignment: .topTrailing) {
                if balanceCheck {
                    Label("Saldo-check", systemImage: "gift")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(7)
                        .accessibilityLabel("Saldo checken kan")
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
