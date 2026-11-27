import SwiftUI
import SwiftData
import CoreLocation

/// The home screen: cards stacked like Apple Wallet. Tapping one brings it forward, larger and
/// fully bright, and turns it over to show the barcode or QR code on the back.
struct WalletView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    /// Set by a widget tap; the card is brought forward and the value cleared.
    @Binding var openCardID: UUID?

    init(openCardID: Binding<UUID?>) {
        _openCardID = openCardID
    }

    /// Het item vooraan (bij een groep tickets: het id van het eerste ticket) en het ticket dat je nu ziet.
    @State private var selectedID: UUID?
    @State private var pageID: UUID?
    /// Filter naast de plusknop (blijft bewaard): alle, favorieten, klantenkaarten, cadeaukaarten, privé, gedeeld, tijdelijk.
    @AppStorage("pasr.walletFilter") private var filterRaw = WalletFilter.all.rawValue
    private var groups = GroupService.shared
    /// Opnieuw tekenen als het beheer winkels (logo, kaartontwerp) bijwerkt.
    private var catalog = StoreCatalog.shared
    /// Volgorde (CardOrder): standaard A tot Z; of meest gebruikt, dichtstbij, of in de buurt en dan meest gebruikt.
    @AppStorage(CardOrder.key) private var order = CardOrder.az.rawValue
    private var cardOrder: CardOrder { CardOrder(rawValue: order) ?? .az }
    @State private var distances: [UUID: CLLocationDistance] = [:]
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var sheet: Sheet?
    @State private var deleting: Card?
    /// Sinds wanneer de barcode in beeld is, en hoe lang al eerder (de app op de achtergrond telt niet mee).
    @State private var codeVisibleSince: Date?
    @State private var codeVisible: TimeInterval = 0
    /// "Gebruikt bij PLUS? Ja · Nee" onderin na het sluiten.
    @State private var usePrompt: UsePrompt?
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    /// 0 = front, 180 = back with the code.
    @State private var flipAngle: Double = 0
    @Namespace private var namespace

    private let peek: CGFloat = 62

    /// Buiten de complexe SwiftUI view-builder houden om compiler-timeouts te voorkomen.
    private var receiptRepairFingerprint: String {
        let receiptKeys = receipts.map { receipt in
            receipt.id.uuidString + ":" + String(receipt.updatedAt.timeIntervalSince1970)
        }
        let cardKeys = cards.map { card in card.id.uuidString }.sorted()
        return receiptKeys.joined(separator: "|") + "#" + cardKeys.joined(separator: "|")
    }

    enum Sheet: Identifiable {
        case add, importScreenshots, settings, edit(Card), share(Card), history(Card), spend(Card, String?), info(Card)
        /// Bonnetjes: alle bonnen (eventueel met een zoekterm), of één bon.
        case receipts(String), receipt(Receipt), coupons, benefits
        /// "Laatst gebruikt": alles, of het bedrag bij één keer.
        case uses(Card), useAmount(Card, UUID)
        var id: String {
            switch self {
            case .uses(let card): "uses-\(card.id)"
            case .receipts: "receipts"
            case .coupons: "coupons"
            case .benefits: "benefits"
            case .receipt(let r): "receipt-\(r.id)"
            case .useAmount(let card, let use): "useAmount-\(card.id)-\(use)"
            case .info(let card): "info-\(card.id)"
            case .history(let card): "history-\(card.id)"
            case .spend(let card, _): "spend-\(card.id)"
            case .add: "add"
            case .importScreenshots: "import"
            case .settings: "settings"
            case .edit(let card): "edit-\(card.id)"
            case .share(let card): "share-\(card.id)"
            }
        }
    }

    private var filter: WalletFilter { WalletFilter(rawValue: filterRaw) ?? .all }

    /// De stapel: tickets voor hetzelfde evenement op dezelfde dag zijn één item (TicketGroups.swift). Een groep staat
    /// erin als één van zijn tickets bij het filter en de zoekterm past.
    private var visibleItems: [CardStackItem] {
        let items = cards.ordered(cardOrder, distances: distances).stackItems()
        let query = search.trimmingCharacters(in: .whitespaces)
        return items.filter { item in
            item.cards.contains { card in
                filter.matches(card) && (query.isEmpty || card.storeName.localizedCaseInsensitiveContains(query)
                    || card.number.contains(query) || card.note.localizedCaseInsensitiveContains(query))
            }
        }
    }

    /// Het item vooraan: een losse kaart of de hele groep tickets.
    private var selectedItem: CardStackItem? {
        guard let selectedID else { return nil }
        return cards.alphabetical().stackItems().first { $0.contains(selectedID) }
    }

    /// De kaart die je nu ziet (bij een groep: het ticket waar je naartoe veegde).
    private var selectedCard: Card? {
        guard let selectedID else { return nil }
        let id = pageID ?? selectedID
        return cards.first { $0.id == id } ?? cards.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let width = min(geo.size.width - 32, 440)
                ZStack {
                    if cards.isEmpty {
                        emptyState
                    } else if visibleItems.isEmpty && filter != .all {
                        filteredEmpty
                    } else {
                        stack(width: width)
                            .blur(radius: selectedID == nil ? 0 : 14)
                            .allowsHitTesting(selectedID == nil)
                    }
                    if let card = selectedCard {
                        forward(card, group: selectedItem.flatMap { $0.isGroup ? $0.cards : nil },
                                width: min(geo.size.width - 24, 470), height: geo.size.height)
                    }
                    if selectedID == nil, !search.trimmingCharacters(in: .whitespaces).isEmpty, !matchingReceipts.isEmpty {
                        receiptMatches
                    }
                }
                .overlay(alignment: .bottom) {
                    if let prompt = usePrompt {
                        UsePromptBar(prompt: prompt, card: cards.first { $0.id == prompt.cardID },
                                     onYes: { confirmUse(prompt) },
                                     onNo: { withAnimation(.snappy) { usePrompt = nil } })
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .id(prompt.id)
                            .task(id: prompt.id) {
                                try? await Task.sleep(for: .seconds(UseCapture.promptDuration))
                                // geen reactie: niet tellen
                                if usePrompt?.id == prompt.id { withAnimation(.snappy) { usePrompt = nil } }
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: geo.size) { _, _ in ScreenBrightness.screenChanged() }
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle(selectedID == nil ? (filter == .all ? String(localized: "Kaarten") : filter.title(groups: groups)) : "")
            .toolbar { toolbar }
            .searchable(text: $search, prompt: Text("Zoek kaarten"))
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add: AddCardView()
            case .importScreenshots: ImportView()
            case .settings: SettingsView()
            case .edit(let card): NavigationStack { CardEditorView(card: card) }
            case .share(let card): ShareCardSheet(card: card)
            case .history(let card): CardHistorySheet(card: card)
            case .uses(let card): RecentUsesView(card: card)
            case .useAmount(let card, let use): UseAmountSheet(card: card, useID: use, offersReceipt: true)
            case .receipts(let query): ReceiptsView(initialQuery: query)
            case .coupons: PasrCouponsView()
            case .benefits: PasrBenefitsView()
            case .receipt(let r): ReceiptDetailView(receipt: r)
            case .info(let card):
                CardInfoSheet(card: card) {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        deleting = card
                    }
                }
            case .spend(let card, let place):
                SpendSheet(card: card, mode: .spent, place: place, asked: true)
                    .presentationDetents([.medium])
            }
        }
        .confirmationDialog(Text("\(deleting?.storeName ?? "kaart") verwijderen?"),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Verwijder", role: .destructive) {
                deleting?.deletedAt = .now
                deleting = nil
                deselect()
            }
        }
        .onChange(of: selectedID) { _, newValue in
            if newValue != nil { ScreenBrightness.boost() } else { ScreenBrightness.restore() }
        }
        .onChange(of: scenePhase) { _, phase in
            // op de achtergrond is de barcode niet in beeld
            if phase != .active, let since = codeVisibleSince {
                codeVisible += Date.now.timeIntervalSince(since)
                codeVisibleSince = nil
            } else if phase == .active, selectedID != nil, codeVisibleSince == nil, flipAngle == 180 {
                codeVisibleSince = .now
            }
        }
        .onDisappear { ScreenBrightness.restore() }
        .task(id: "\(catalog.version)|" + WidgetSync.fingerprint(of: cards)) { WidgetSync.update(with: cards) }
        // bonnetjes in Spotlight (alleen de index op dit toestel)
        .task(id: receiptRepairFingerprint) {
            // Herstel ook al opgeslagen bonnetjes uit oudere builds (bijv. Action),
            // zonder dubbele gebruiksmomenten of wijzigingen aan cadeaukaarttegoed.
            ReceiptUseLinker.reconcile(receipts, cards: cards, context: context)
            ReceiptSpotlight.index(receipts)
        }
        .task(id: "\(order)|\(scenePhase == .active)|\(cards.count)") { await updateDistances(search: false) }
        .onChange(of: openCardID, initial: true) { _, id in openRequestedCard(id) }
        .onReceive(NotificationCenter.default.publisher(for: .pasrCloseSheets)) { _ in sheet = nil }
        .onReceive(NotificationCenter.default.publisher(for: .pasrOpenReceipt)) { _ in openPendingReceipt() }
        .onAppear { openPendingReceipt() }
        .onChange(of: cards.count) { _, _ in openRequestedCard(openCardID) }
    }

    /// Afstanden voor "Dichtstbij eerst" (uit wat Pasr al weet; met `search` ook filialen opzoeken).
    private func updateDistances(search: Bool) async {
        guard cardOrder.usesLocation else { distances = [:]; return }
        let stores = NearbyStores.shared
        var here = await stores.currentLocation(maxAge: 300)
        if let h = here { distances = stores.knownDistances(for: cards, from: h) }
        if search || (here != nil && distances.count < min(cards.count, 3)) {
            here = await stores.updateBranches(cards: cards) ?? here
            if let h = here { distances = stores.knownDistances(for: cards, from: h) }
        }
        WidgetSync.update(with: cards)   // widgets en Watch in dezelfde volgorde
    }

    /// Omlaag trekken: account en gedeelde Pasrs synchroniseren en de winkels om je heen opnieuw zoeken.
    private func pullToRefresh() async {
        if cardOrder.usesLocation { await updateDistances(search: true) } else { await NearbyStores.shared.refresh(cards: cards, force: true) }
        if AccountService.shared.isSignedIn {
            await CardSync.sync(in: context)
            await GroupService.shared.sync(in: context)
        }
        await BusinessCards.refreshAll(in: context, force: true)
    }

    private func openRequestedCard(_ id: UUID?) {
        guard let id, cards.contains(where: { $0.id == id }),
              let item = cards.alphabetical().stackItems().first(where: { $0.contains(id) }) else { return }
        openCardID = nil
        sheet = nil
        // een ticket uit een groep: de groep vooraan, op dat ticket
        if selectedID != item.id || (pageID ?? selectedID) != id { select(item, page: id) }
    }

    // MARK: Stack

    private func stack(width: CGFloat) -> some View {
        let height = width / Brand.cardAspect
        let list = visibleItems
        return ScrollView {
            ZStack(alignment: .top) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                    let card = item.first
                    Group {
                        if selectedID == item.id {
                            Color.clear
                        } else if item.isGroup {
                            TicketGroupStackFace(item: item)
                                .matchedGeometryEffect(id: item.id, in: namespace)
                        } else {
                            CardFaceView(appearance: CardAppearance(card), showsCode: false)
                                .matchedGeometryEffect(id: card.id, in: namespace)
                        }
                    }
                    .frame(width: width, height: height)
                    .offset(y: CGFloat(index) * peek)
                    .zIndex(Double(index))
                    .onTapGesture { select(item) }
                    .contextMenu { if item.isGroup { groupMenu(item) } else { cardMenu(card) } }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(item.isGroup ? Text("Opent de tickets; veeg naar links of rechts voor het volgende ticket")
                                                    : Text("Haalt de kaart naar voren"))
                }
            }
            .frame(height: CGFloat(max(list.count - 1, 0)) * peek + height + 24, alignment: .top)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .refreshable { await pullToRefresh() }
    }

    @ViewBuilder private func cardMenu(_ card: Card) -> some View {
        Button { sheet = .edit(card) } label: { Label("Wijzig", systemImage: "pencil") }
        if !card.isTemporary {
            Button { share(card) } label: { Label("Deel", systemImage: "square.and.arrow.up") }
        }
        Button {
            card.isFavorite.toggle()
            card.updatedAt = .now
        } label: {
            Label(card.isFavorite ? "Geen favoriet" : "Favoriet", systemImage: card.isFavorite ? "star.slash" : "star")
        }
        Button(role: .destructive) { deleting = card } label: { Label("Verwijder", systemImage: "trash") }
    }

    /// Contextmenu van een groep tickets: openen, of per ticket wijzigen.
    @ViewBuilder private func groupMenu(_ item: CardStackItem) -> some View {
        Button { select(item) } label: { Label("Open \(item.countText)", systemImage: "ticket") }
        ForEach(item.cards) { card in
            Button { sheet = .edit(card) } label: { Label("Wijzig \(card.storeName)", systemImage: "pencil") }
        }
    }

    // MARK: Card brought forward

    private func forward(_ card: Card, group: [Card]?, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.45))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { deselect() }
                .transition(.opacity)

            // in een ScrollView: met "Laatst gebruikt" en grote tekst past het niet altijd op het scherm
            ScrollView {
                VStack(spacing: 22) {
                    if let group, let first = group.first {
                        // groep tickets: horizontaal vegen naar het volgende ticket, elk met zijn eigen code
                        TicketGroupPager(cards: group,
                                         page: Binding(get: { pageID ?? first.id },
                                                       set: { new in pageID = new }),
                                         angle: flipAngle, width: width)
                            .matchedGeometryEffect(id: first.id, in: namespace)
                    } else {
                        // tijdelijke kaart: elke 15 seconden opnieuw tekenen, zodat de code op het einde verdwijnt
                        TimelineView(.periodic(from: .now, by: card.isTemporary ? 15 : 3600)) { _ in
                            FlipCardView(appearance: CardAppearance(card), angle: flipAngle)
                        }
                            .frame(width: width, height: width / Brand.cardAspect)
                            .matchedGeometryEffect(id: card.id, in: namespace)
                            .shadow(color: .black.opacity(0.5), radius: 30, y: 20)
                            .onTapGesture { deselect() }
                    }

                    HStack(spacing: 14) {
                        actionButton(card.isFavorite ? "star.fill" : "star",
                                     label: card.isFavorite ? "Geen favoriet" : "Favoriet") {
                            card.isFavorite.toggle()
                            card.updatedAt = .now
                        }
                        actionButton("pencil", label: "Wijzig") { sheet = .edit(card) }
                        // cadeaukaart: tegoed en uitgaven; andere kaarten: Laatst gebruikt (vervangt de oude geschiedenis)
                        actionButton(card.kind == .voucher ? "eurosign.circle" : "clock.arrow.circlepath",
                                     label: card.kind == .voucher ? "Tegoed en uitgaven" : "Laatst gebruikt") {
                            sheet = card.kind == .voucher ? .history(card) : .uses(card)
                        }
                        if !card.isTemporary {
                            actionButton("square.and.arrow.up", label: "Deel") { share(card) }
                        }
                        // tijdelijk gedeelde kaarten mogen niet in Apple Wallet
                        if WalletPass.isAvailable, WalletPass.canMakePass(card) {
                            WalletActionButton(card: card).id(card.id)
                        }
                        // details (gids, foto's, ticket, abonnement) en verwijderen, zoals de achterkant van een pas in Wallet
                        actionButton("info.circle", label: "Details") { sheet = .info(card) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                    if card.kind == .stamps {
                        StampControls(card: card, width: width)
                            .transition(.opacity)
                    }

                    if !card.note.isEmpty {
                        Text(card.note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(width: width, alignment: .leading)
                    }

                    // Laatst gebruikt (zoals de transacties in Apple Wallet): de laatste 3 keer, met wat je uitgaf
                    RecentUsesSection(card: card,
                                      onAll: { sheet = .uses(card) },
                                      onAmount: { use in sheet = .useAmount(card, use.id) })
                        .frame(width: width)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, minHeight: height)
                // leeg vlak naast de inhoud: tikken legt de kaart terug
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { deselect() })
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func actionButton(_ symbol: String, label: LocalizedStringKey, role: ButtonRole? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(label, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 30, height: 30)
        }
        .pasrGlassButton()
        .accessibilityLabel(Text(label))
    }

    /// Sharing a locked card asks for Face ID first; the link contains the code.
    private func share(_ card: Card) {
        guard card.isLocked else { sheet = .share(card); return }
        Task {
            if await Biometrics.authenticate(reason: String(localized: "Bevestig om deze kaart te delen.")) {
                sheet = .share(card)
            }
        }
    }

    /// Een losse kaart of een groep tickets naar voren (bij een groep op `page`, anders het eerste ticket).
    private func select(_ item: CardStackItem, page: UUID? = nil) {
        let shown = item.cards.first { $0.id == page } ?? item.first
        if item.cards.contains(where: \.isLocked) {
            Task {
                guard await Biometrics.authenticate(reason: String(localized: "Bevestig dat jij het bent om de code te tonen.")) else { return }
                bringForward(shown, item: item)
            }
        } else {
            bringForward(shown, item: item)
        }
    }

    private func bringForward(_ card: Card, item: CardStackItem? = nil) {
        pageID = item?.isGroup == true ? card.id : nil
        // telt voor de volgorde "Meest gebruikt"; in Laatst gebruikt komt pas iets na "Ja" bij het sluiten
        card.markUsed()
        withAnimation(.snappy) { usePrompt = nil }
        codeVisible = 0
        codeVisibleSince = nil
        let id = item?.id ?? card.id
        Task { @MainActor in
            // de barcode staat in beeld zodra de kaart is omgedraaid
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 350 : 900))
            if selectedID == id, scenePhase == .active { codeVisibleSince = .now }
        }
        flipAngle = 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.82)) { selectedID = item?.id ?? card.id }
        // Once it's in front, turn it over to show the code.
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15).delay(0.15) : .spring(response: 0.62, dampingFraction: 0.78).delay(0.28)) { flipAngle = 180 }
    }

    private func deselect() {
        guard let id = selectedID else { return }
        // Barcode minstens 5 seconden in beeld: onderin vragen of je de kaart gebruikte (met Alleen bij de winkel
        // alleen als je bij een filiaal bent). Geen reactie of Nee: er komt niets bij.
        let visible = codeVisible + (codeVisibleSince.map { Date.now.timeIntervalSince($0) } ?? 0)
        codeVisible = 0
        codeVisibleSince = nil
        if let card = cards.first(where: { $0.id == (pageID ?? id) }) {
            Task { @MainActor in
                let decision = await UseCapture.decide(for: card, visible: visible)
                guard decision.ask, selectedID == nil || selectedID == id else { return }   // niet over een andere kaart heen
                let title = decision.place ?? (card.storeName.isEmpty ? String(localized: "deze winkel") : card.storeName)
                withAnimation(.snappy) { usePrompt = UsePrompt(cardID: card.id, title: title, place: decision.place) }
            }
        }
        withAnimation(.easeInOut(duration: 0.32)) { flipAngle = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.86)) { selectedID = nil; pageID = nil }
        }
    }

    /// Bonnetje uit een garantieherinnering, Spotlight of de opdracht "Toon bonnetje".
    private func openPendingReceipt() {
        guard let id = NotificationRouter.pendingReceiptID else { return }
        NotificationRouter.pendingReceiptID = nil
        Task { @MainActor in
            // de query kan net een tel later zijn bijgewerkt
            for _ in 0..<10 {
                if let r = receipts.first(where: { $0.id == id }) {
                    if selectedID != nil { deselect() }
                    sheet = .receipt(r)
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    /// "Ja": het moment komt in Laatst gebruikt, daarna optioneel het bedrag (bij een cadeaukaart van het tegoed).
    private func confirmUse(_ prompt: UsePrompt) {
        withAnimation(.snappy) { usePrompt = nil }
        guard let card = cards.first(where: { $0.id == prompt.cardID }) else { return }
        let use = card.recordUse(place: prompt.place, source: "ask")
        try? context.save()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if sheet == nil { sheet = .useAmount(card, use) }
        }
    }

    // MARK: Bonnetjes in de zoekresultaten

    private var matchingReceipts: [Receipt] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return receipts.filter { $0.matches(q) }
    }

    /// Onder de gevonden kaarten: de bonnetjes die bij de zoekterm passen (winkel, bedrag of datum).
    private var receiptMatches: some View {
        let list = matchingReceipts
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(list.count == 1 ? String(localized: "1 bonnetje") : String(localized: "\(list.count) bonnetjes"),
                      systemImage: "doc.text.fill")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button("Alles") { sheet = .receipts(search) }
                    .font(.subheadline.weight(.semibold))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(list.prefix(12)) { r in
                        Button { sheet = .receipt(r) } label: { ReceiptChip(receipt: r) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: Empty state and toolbar

    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                ForEach(Array([Brand.mint, Brand.iris, Brand.coral].enumerated()), id: \.offset) { i, color in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color.gradient)
                        .frame(width: 120, height: 120 / Brand.cardAspect)
                        .rotationEffect(.degrees(Double(i - 1) * 9))
                        .offset(x: CGFloat(i - 1) * 18, y: CGFloat(i) * 8)
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
                }
            }
            .frame(height: 120)
            VStack(spacing: 8) {
                Text("Al je kaarten, één tik verderop").font(.title2.bold())
                Text("Voeg klantenkaarten en vouchers toe. Ze synchroniseren via je eigen iCloud en staan ook op je Apple Watch.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            VStack(spacing: 10) {
                Button { sheet = .add } label: {
                    Label("Kaart toevoegen", systemImage: "plus").frame(maxWidth: 260).padding(.vertical, 6)
                }
                .pasrGlassButton(prominent: true)
                .tint(Brand.iris)
                Button { sheet = .importScreenshots } label: {
                    Label("Importeren uit andere app", systemImage: "square.and.arrow.down.on.square").frame(maxWidth: 260).padding(.vertical, 6)
                }
                .pasrGlassButton()
                #if DEBUG
                Button("Voorbeeldkaarten laden") { PasrStore.insertSamples(into: context) }
                    .font(.footnote).padding(.top, 4)
                #endif
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Filterknop naast de plus: gevuld icoon als er een filter aanstaat.
    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: Binding(get: { filterRaw }, set: { new in withAnimation(.snappy) { filterRaw = new } })) {
                ForEach(WalletFilter.basic + WalletFilter.extra.filter { f in cards.contains { f.matches($0) } }, id: \.self) { f in
                    Label(f.title, systemImage: f.symbol).tag(f.rawValue)
                }
            }
            Picker("Volgorde", selection: Binding(get: { order }, set: { new in
                withAnimation(.snappy) { order = new }
                if CardOrder(rawValue: new)?.usesLocation == true {
                    Task { _ = await NearbyStores.shared.locationForPin(); await updateDistances(search: true) }
                }
                WidgetSync.update(with: cards)
            })) {
                ForEach(CardOrder.allCases) { o in Label(o.title, systemImage: o.symbol).tag(o.rawValue) }
            }
            let shared = cards.contains { $0.groupID != nil }
            let temporary = cards.contains(where: \.isTemporary)
            if shared || temporary {
                Picker("Delen", selection: Binding(get: { filterRaw }, set: { new in withAnimation(.snappy) { filterRaw = new } })) {
                    Label(WalletFilter.personal.title, systemImage: WalletFilter.personal.symbol).tag(WalletFilter.personal.rawValue)
                    if shared {
                        ForEach(groups.groups) { g in
                            Label(g.name, systemImage: "person.2.fill").tag(WalletFilter.group(g.id).rawValue)
                        }
                    }
                    if temporary {
                        Label(WalletFilter.temporary.title, systemImage: WalletFilter.temporary.symbol).tag(WalletFilter.temporary.rawValue)
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityValue(Text(filter.title(groups: groups)))
    }

    private var filteredEmpty: some View {
        VStack(spacing: 14) {
            Image(systemName: filter.symbol).font(.system(size: 40, weight: .semibold)).foregroundStyle(.secondary)
            Text("Geen kaarten bij \(filter.title(groups: groups))").font(.headline)
            Button("Toon alle kaarten") { withAnimation(.snappy) { filterRaw = WalletFilter.all.rawValue } }
                .pasrGlassButton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if selectedID != nil {
                Button("Klaar", systemImage: "xmark") { deselect() }
            } else {
                Button { sheet = .settings } label: { Label("Instellingen", systemImage: "gearshape") }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if selectedID == nil {
                Button { sheet = .coupons } label: { Label("Kortingsbonnen", systemImage: "ticket") }
                Button { sheet = .benefits } label: { Label("Mijn voordelen", systemImage: "gift") }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            // vaste ingang naar alle bonnetjes (nieuwste eerst, zoeken op winkel, bedrag of datum)
            if selectedID == nil, !cards.isEmpty || !receipts.isEmpty {
                Button { sheet = .receipts("") } label: { Label("Bonnetjes", systemImage: "doc.text") }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if selectedID == nil, !cards.isEmpty { filterMenu }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { sheet = .add } label: { Label("Kaart toevoegen", systemImage: "plus.rectangle.on.rectangle") }
                Button { sheet = .importScreenshots } label: { Label("Importeren uit andere app", systemImage: "square.and.arrow.down.on.square") }
            } label: {
                Label("Toevoegen", systemImage: "plus")
            }
        }
    }
}

/// Turns the screen fully bright while a code is shown, like Wallet does.
/// Per scherm: op iPhone Duo kan de app tijdens het tonen van het binnen- naar het buitenscherm gaan (open- of
/// dichtklappen). Dan krijgt het nieuwe scherm ook volle helderheid en elk scherm later zijn eigen stand terug.
enum ScreenBrightness {
    #if os(iOS)
    @MainActor private static var saved: [ObjectIdentifier: (screen: UIScreen, brightness: CGFloat)] = [:]
    @MainActor private static var active = false

    @MainActor static func boost() {
        active = true
        UIApplication.shared.isIdleTimerDisabled = true
        guard let screen = currentScreen else { return }
        let id = ObjectIdentifier(screen)
        if saved[id] == nil { saved[id] = (screen, screen.brightness) }
        screen.brightness = 1
    }

    /// Het scherm van de app veranderde (iPhone Duo open- of dichtgeklapt): als er een code staat, ook dat scherm fel.
    @MainActor static func screenChanged() {
        if active { boost() }
    }

    @MainActor static func restore() {
        guard active else { return }
        active = false
        for (_, entry) in saved { entry.screen.brightness = entry.brightness }
        saved = [:]
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Het scherm van de scene die nu vooraan staat (niet UIScreen.main: op een toestel met twee schermen is dat
    /// niet eenduidig).
    @MainActor private static var currentScreen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }
    #else
    static func boost() {}
    static func screenChanged() {}
    static func restore() {}
    #endif
}

/// Filter van de kaartenstapel.
enum WalletFilter: Hashable {
    case all, favorites, loyalty, voucher, stamps, code, ticket, subscription, personal, temporary
    case group(UUID)

    static let basic: [WalletFilter] = [.all, .favorites, .loyalty, .voucher]
    /// Alleen in het menu als je zo'n pas hebt.
    static let extra: [WalletFilter] = [.stamps, .code, .ticket, .subscription]

    init?(rawValue: String) {
        switch rawValue {
        case "all": self = .all
        case "favorites": self = .favorites
        case "loyalty": self = .loyalty
        case "voucher": self = .voucher
        case "code": self = .code
        case "stamps": self = .stamps
        case "ticket": self = .ticket
        case "subscription": self = .subscription
        case "personal": self = .personal
        case "temporary": self = .temporary
        default:
            guard rawValue.hasPrefix("group:"), let id = UUID(uuidString: String(rawValue.dropFirst(6))) else { return nil }
            self = .group(id)
        }
    }

    var rawValue: String {
        switch self {
        case .all: "all"
        case .favorites: "favorites"
        case .loyalty: "loyalty"
        case .voucher: "voucher"
        case .code: "code"
        case .stamps: "stamps"
        case .ticket: "ticket"
        case .subscription: "subscription"
        case .personal: "personal"
        case .temporary: "temporary"
        case .group(let id): "group:\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .all: String(localized: "Alle kaarten")
        case .favorites: String(localized: "Favorieten")
        case .loyalty: String(localized: "Klantenkaarten")
        case .voucher: String(localized: "Cadeaukaarten en vouchers")
        case .code: String(localized: "Kortingscodes")
        case .stamps: String(localized: "Stempelkaarten")
        case .ticket: String(localized: "Tickets")
        case .subscription: String(localized: "Abonnementen")
        case .personal: String(localized: "Alleen privé")
        case .temporary: String(localized: "Tijdelijk met mij gedeeld")
        case .group: String(localized: "Gedeelde Pasr")
        }
    }

    @MainActor func title(groups: GroupService) -> String {
        if case .group(let id) = self { return groups.group(id)?.name ?? title }
        return title
    }

    var symbol: String {
        switch self {
        case .all: "rectangle.stack"
        case .favorites: "star.fill"
        case .loyalty: "creditcard"
        case .voucher: "giftcard"
        case .code: CardKind.code.symbol
        case .stamps: CardKind.stamps.symbol
        case .ticket: CardKind.ticket.symbol
        case .subscription: CardKind.subscription.symbol
        case .personal: "person.fill"
        case .temporary: "clock.fill"
        case .group: "person.2.fill"
        }
    }

    func matches(_ card: Card) -> Bool {
        switch self {
        case .all: true
        case .favorites: card.isFavorite
        case .loyalty: card.kind == .loyalty
        case .voucher: card.kind == .voucher
        case .code: card.kind == .code
        case .stamps: card.kind == .stamps
        case .ticket: card.kind == .ticket
        case .subscription: card.kind == .subscription
        case .personal: card.groupID == nil && !card.isTemporary
        case .temporary: card.isTemporary
        case .group(let id): card.groupID == id
        }
    }
}
