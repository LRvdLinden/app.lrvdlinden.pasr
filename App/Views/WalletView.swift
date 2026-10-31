import SwiftUI
import SwiftData

/// The home screen: cards stacked like Apple Wallet. Tapping a card lifts it to the top
/// with its code; the rest drop into a pile at the bottom.
struct WalletView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]

    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var sheet: Sheet?
    @State private var confirmDelete = false
    @Namespace private var namespace

    private let peek: CGFloat = 62

    enum Sheet: Identifiable {
        case add, importScreenshots, settings, edit(Card)
        var id: String {
            switch self {
            case .add: "add"
            case .importScreenshots: "import"
            case .settings: "settings"
            case .edit(let card): "edit-\(card.id)"
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
                ZStack(alignment: .top) {
                    if cards.isEmpty {
                        emptyState
                    } else {
                        stack(width: width)
                            .opacity(selectedID == nil ? 1 : 0)
                            .allowsHitTesting(selectedID == nil)
                        if let card = selectedCard {
                            detail(card, width: width, height: geo.size.height)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
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
            }
        }
        .onChange(of: selectedID) { _, newValue in
            if newValue != nil { ScreenBrightness.boost() } else { ScreenBrightness.restore() }
        }
        .onDisappear { ScreenBrightness.restore() }
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
                            CardFaceView(appearance: CardAppearance(card))
                                .matchedGeometryEffect(id: card.id, in: namespace)
                        }
                    }
                        .frame(width: width, height: height)
                        .offset(y: CGFloat(index) * peek)
                        .zIndex(Double(index))
                        .onTapGesture { select(card) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text("Toont de code"))
                }
            }
            .frame(height: CGFloat(max(list.count - 1, 0)) * peek + height + 24, alignment: .top)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Detail

    private func detail(_ card: Card, width: CGFloat, height: CGFloat) -> some View {
        let others = visibleCards.filter { $0.id != card.id }.prefix(4)
        return ZStack(alignment: .top) {
            Color.clear.contentShape(Rectangle()).onTapGesture { deselect() }

            VStack(spacing: 18) {
                CardFaceView(appearance: CardAppearance(card), expanded: true)
                    .frame(width: width)
                    .matchedGeometryEffect(id: card.id, in: namespace)
                    .onTapGesture { deselect() }
                    .padding(.top, 8)

                HStack(spacing: 12) {
                    actionButton(card.isFavorite ? "star.fill" : "star",
                                 label: card.isFavorite ? "Geen favoriet" : "Favoriet") {
                        card.isFavorite.toggle()
                        card.updatedAt = .now
                    }
                    actionButton("pencil", label: "Wijzig") { sheet = .edit(card) }
                    actionButton("trash", label: "Verwijder", role: .destructive) { confirmDelete = true }
                }
                if !card.note.isEmpty {
                    Text(card.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: width, alignment: .leading)
                }
            }

            // The other cards wait in a pile at the bottom, like Wallet.
            ZStack(alignment: .top) {
                ForEach(Array(others.enumerated()), id: \.element.id) { index, other in
                    CardFaceView(appearance: CardAppearance(other))
                        .frame(width: width, height: width / Brand.cardAspect)
                        .scaleEffect(1 - CGFloat(others.count - 1 - index) * 0.03, anchor: .top)
                        .offset(y: CGFloat(index) * 9)
                        .onTapGesture { select(other) }
                }
            }
            .offset(y: height - 72)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .frame(height: height, alignment: .top)
        .clipped()
        .confirmationDialog(Text("\(card.storeName) naar Recent verwijderd verplaatsen?"), isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Verwijder", role: .destructive) {
                card.deletedAt = .now
                deselect()
            }
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

    private func select(_ card: Card) {
        card.markUsed()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) { selectedID = card.id }
    }

    private func deselect() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { selectedID = nil }
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
