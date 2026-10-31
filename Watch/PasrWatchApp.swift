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

/// Cards stacked as passes, like the Wallet app on Apple Watch: scroll with the Digital Crown,
/// tap a pass to show it with its code.
struct WatchWalletView: View {
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]

    var body: some View {
        NavigationStack {
            if cards.isEmpty {
                ContentUnavailableView("Nog geen kaarten", systemImage: "wallet.pass",
                                       description: Text("Voeg kaarten toe in Pasr op je iPhone. Ze verschijnen hier via iCloud."))
            } else {
                GeometryReader { geo in
                    let width = geo.size.width
                    let height = width / Brand.cardAspect
                    ScrollView {
                        // Each pass shows only its top strip, except the last one.
                        VStack(spacing: -(height - 40)) {
                            ForEach(Array(cards.smartSorted().enumerated()), id: \.element.id) { index, card in
                                NavigationLink(value: card.id) {
                                    CardFaceView(appearance: CardAppearance(card), showsCode: false, cornerRadius: 12)
                                        .frame(width: width, height: height)
                                }
                                .buttonStyle(.plain)
                                .zIndex(Double(index))
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
                .navigationTitle("Pasr")
                .navigationDestination(for: UUID.self) { id in
                    if let card = cards.first(where: { $0.id == id }) {
                        WatchPassView(card: card)
                    }
                }
            }
        }
    }
}

/// One pass with its code, as large as the screen allows. Tap to switch to the code alone on white.
struct WatchPassView: View {
    let card: Card
    @State private var codeOnly = false

    var body: some View {
        Group {
            if codeOnly {
                VStack(spacing: 6) {
                    BarcodeView(value: card.number, format: card.format, codeImage: card.codeImage)
                        .frame(maxHeight: card.format.isLinear ? 80 : .infinity)
                    Text(CardAppearance(card).groupedNumber)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white)
                .ignoresSafeArea()
            } else {
                CardFaceView(appearance: CardAppearance(card), revealed: true, cornerRadius: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 2)
            }
        }
        .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { codeOnly.toggle() } }
        .navigationTitle(card.storeName)
        .onAppear { card.markUsed() }
    }
}
