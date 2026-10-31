import SwiftUI
import SwiftData

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

    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var sheet: Sheet?
    @State private var deleting: Card?
    /// 0 = front, 180 = back with the code.
    @State private var flipAngle: Double = 0
    @Namespace private var namespace

    private let peek: CGFloat = 62

    enum Sheet: Identifiable {
        case add, importScreenshots, settings, edit(Card), share(Card)
        var id: String {
            switch self {
            case .add: "add"
            case .importScreenshots: "import"
            case .settings: "settings"
            case .edit(let card): "edit-\(card.id)"
            case .share(let card): "share-\(card.id)"
            }
        }
    }

    private var visibleCards: [Card] {
        let sorted = cards.smartSorted()
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.storeName.localizedCaseInsensitiveContains(query) || $0.number.contains(query)
                || $0.note.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedCard: Card? { cards.first { $0.id == selectedID } }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let width = min(geo.size.width - 32, 440)
                ZStack {
                    if cards.isEmpty {
                        emptyState
                    } else {
                        stack(width: width)
                            .blur(radius: selectedID == nil ? 0 : 14)
                            .allowsHitTesting(selectedID == nil)
                    }
                    if let card = selectedCard {
                        forward(card, width: min(geo.size.width - 24, 470))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle(selectedID == nil ? String(localized: "Kaarten") : "")
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
            }
        }
        .confirmationDialog(Text("\(deleting?.storeName ?? "") naar Recent verwijderd verplaatsen?"),
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
        .onDisappear { ScreenBrightness.restore() }
        .task(id: WidgetSync.fingerprint(of: cards)) { WidgetSync.update(with: cards) }
        .onChange(of: openCardID, initial: true) { _, id in openRequestedCard(id) }
        .onChange(of: cards.count) { _, _ in openRequestedCard(openCardID) }
    }

    private func openRequestedCard(_ id: UUID?) {
        guard let id, let card = cards.first(where: { $0.id == id }) else { return }
        openCardID = nil
        sheet = nil
        if selectedID != id { select(card) }
    }

    // MARK: Stack

    private func stack(width: CGFloat) -> some View {
        let height = width / Brand.cardAspect
        let list = visibleCards
        return ScrollView {
            ZStack(alignment: .top) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, card in
                    Group {
                        if selectedID == card.id {
                            Color.clear
                        } else {
                            CardFaceView(appearance: CardAppearance(card), showsCode: false)
                                .matchedGeometryEffect(id: card.id, in: namespace)
                        }
                    }
                    .frame(width: width, height: height)
                    .offset(y: CGFloat(index) * peek)
                    .zIndex(Double(index))
                    .onTapGesture { select(card) }
                    .contextMenu { cardMenu(card) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text("Haalt de kaart naar voren"))
                }
            }
            .frame(height: CGFloat(max(list.count - 1, 0)) * peek + height + 24, alignment: .top)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func cardMenu(_ card: Card) -> some View {
        Button { sheet = .edit(card) } label: { Label("Wijzig", systemImage: "pencil") }
        Button { share(card) } label: { Label("Deel", systemImage: "square.and.arrow.up") }
        Button {
            card.isFavorite.toggle()
            card.updatedAt = .now
        } label: {
            Label(card.isFavorite ? "Geen favoriet" : "Favoriet", systemImage: card.isFavorite ? "star.slash" : "star")
        }
        Button(role: .destructive) { deleting = card } label: { Label("Verwijder", systemImage: "trash") }
    }

    // MARK: Card brought forward

    private func forward(_ card: Card, width: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.45))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { deselect() }
                .transition(.opacity)

            VStack(spacing: 22) {
                FlipCardView(appearance: CardAppearance(card), angle: flipAngle)
                    .frame(width: width, height: width / Brand.cardAspect)
                    .matchedGeometryEffect(id: card.id, in: namespace)
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 20)
                    .onTapGesture { deselect() }

                HStack(spacing: 14) {
                    actionButton(card.isFavorite ? "star.fill" : "star",
                                 label: card.isFavorite ? "Geen favoriet" : "Favoriet") {
                        card.isFavorite.toggle()
                        card.updatedAt = .now
                    }
                    actionButton("pencil", label: "Wijzig") { sheet = .edit(card) }
                    actionButton("square.and.arrow.up", label: "Deel") { sheet = .share(card) }
                    actionButton("trash", label: "Verwijder", role: .destructive) { deleting = card }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                if !card.note.isEmpty {
                    Text(card.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: width, alignment: .leading)
                }
            }
            .offset(y: -30)
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
        .buttonStyle(.glass)
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

    private func select(_ card: Card) {
        if card.isLocked {
            Task {
                guard await Biometrics.authenticate(reason: String(localized: "Bevestig dat jij het bent om de code te tonen.")) else { return }
                bringForward(card)
            }
        } else {
            bringForward(card)
        }
    }

    private func bringForward(_ card: Card) {
        card.markUsed()
        flipAngle = 0
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { selectedID = card.id }
        // Once it's in front, turn it over to show the code.
        withAnimation(.spring(response: 0.62, dampingFraction: 0.78).delay(0.28)) { flipAngle = 180 }
    }

    private func deselect() {
        guard selectedID != nil else { return }
        withAnimation(.easeInOut(duration: 0.32)) { flipAngle = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { selectedID = nil }
        }
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
                .buttonStyle(.glassProminent)
                .tint(Brand.iris)
                Button { sheet = .importScreenshots } label: {
                    Label("Screenshots importeren", systemImage: "photo.stack").frame(maxWidth: 260).padding(.vertical, 6)
                }
                .buttonStyle(.glass)
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

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if selectedID != nil {
                Button("Klaar") { deselect() }
            } else {
                Button { sheet = .settings } label: { Label("Instellingen", systemImage: "gearshape") }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { sheet = .add } label: { Label("Kaart toevoegen", systemImage: "plus.rectangle.on.rectangle") }
                Button { sheet = .importScreenshots } label: { Label("Screenshots importeren", systemImage: "photo.stack") }
            } label: {
                Label("Toevoegen", systemImage: "plus")
            }
        }
    }
}

/// Turns the screen fully bright while a code is shown, like Wallet does.
enum ScreenBrightness {
    #if os(iOS)
    @MainActor private static var saved: CGFloat?

    @MainActor static func boost() {
        guard let screen = currentScreen else { return }
        if saved == nil { saved = screen.brightness }
        screen.brightness = 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    @MainActor static func restore() {
        guard let screen = currentScreen, let saved else { return }
        screen.brightness = saved
        Self.saved = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    @MainActor private static var currentScreen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }
    #else
    static func boost() {}
    static func restore() {}
    #endif
}
