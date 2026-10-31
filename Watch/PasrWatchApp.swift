import SwiftUI
import SwiftData

@main
struct PasrWatchApp: App {
    let container = PasrStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            WatchWalletView()
        }
        .modelContainer(container)
    }
}

/// Cards in Wallet style; tap one to show its code full screen.
struct WatchWalletView: View {
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]

    var body: some View {
        NavigationStack {
            if cards.isEmpty {
                ContentUnavailableView("No cards yet", systemImage: "wallet.pass",
                                       description: Text("Add cards in Pasr on your iPhone. They appear here through iCloud."))
            } else {
                ScrollView {
                    LazyVStack(spacing: -18) {
                        ForEach(cards.smartSorted()) { card in
                            NavigationLink(value: card.id) {
                                WatchCardRow(card: card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .navigationTitle("Pasr")
                .navigationDestination(for: UUID.self) { id in
                    if let card = cards.first(where: { $0.id == id }) {
                        WatchCodeView(card: card)
                    }
                }
            }
        }
    }
}

struct WatchCardRow: View {
    let card: Card

    var body: some View {
        let ink = Color.onCard(card.colorHex)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color.shade(card.colorHex, by: 0.14), Color(hex: card.colorHex),
                                              Color.shade(card.colorHex, by: -0.2)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                }
            HStack(spacing: 6) {
                Text(card.storeName)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if card.isFavorite { Image(systemName: "star.fill").font(.caption2) }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
        .frame(height: 76)
        .shadow(color: .black.opacity(0.4), radius: 4, y: -2)
    }
}

/// The code on a white background, as large as the screen allows.
struct WatchCodeView: View {
    let card: Card

    var body: some View {
        VStack(spacing: 6) {
            Text(card.storeName)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(.black.opacity(0.75))
                .lineLimit(1)
            BarcodeView(value: card.number, format: card.format, codeImage: card.codeImage)
                .frame(maxHeight: card.format.isLinear ? 70 : .infinity)
            Text(CardAppearance(card).groupedNumber)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.black.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .ignoresSafeArea(edges: .bottom)
        .onAppear { card.markUsed() }
    }
}
