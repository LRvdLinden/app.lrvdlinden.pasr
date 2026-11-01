import SwiftUI
import SwiftData

import WatchConnectivity

@main
struct PasrWatchApp: App {
    let container = PasrStore.makeContainer()
    @State private var phone = PhoneLink.shared

    var body: some Scene {
        WindowGroup {
            WatchWalletView()
                .environment(phone)
        }
        .modelContainer(container)
    }
}

/// Receives the cards from the iPhone (WatchConnectivity) and keeps the last copy on the Watch,
/// so passes are there within seconds and also without a connection.
@Observable
final class PhoneLink: NSObject, WCSessionDelegate {
    static let shared = PhoneLink()

    private(set) var cards: [WatchCard]?
    private(set) var receivedAt: Date?

    private var file: URL { URL.applicationSupportDirectory.appending(path: "phone-cards.json") }

    override init() {
        super.init()
        if let data = try? Data(contentsOf: file), let list = WatchPayload.decode(data) {
            cards = list
            receivedAt = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Asks the iPhone for the newest cards (it answers with a file transfer).
    func requestCards() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["request": "cards"], replyHandler: nil, errorHandler: nil)
    }

    private func store(_ list: [WatchCard], data: Data?, keepImages: Bool) {
        var list = list
        if keepImages, let old = cards {
            // The quick update has no images: keep the logos and codes we already have.
            let byID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            list = list.map { card in
                var card = card
                if let previous = byID[card.id], previous.number == card.number {
                    card.logo = previous.logo
                    card.code = previous.code
                }
                return card
            }
        }
        let save = keepImages ? WatchPayload.encode(list) : data
        if let save {
            try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try? save.write(to: file, options: .atomic)
        }
        Task { @MainActor in
            self.cards = list
            self.receivedAt = .now
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if !session.receivedApplicationContext.isEmpty {
            self.session(session, didReceiveApplicationContext: session.receivedApplicationContext)
        }
        requestCards()
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context["cards"] as? Data, let list = WatchPayload.decode(data) else { return }
        store(list, data: data, keepImages: true)
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL), let list = WatchPayload.decode(data) else { return }
        store(list, data: data, keepImages: false)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { requestCards() }
    }
}

/// Cards stacked as passes, like the Wallet app on Apple Watch: scroll with the Digital Crown,
/// tap a pass to show it with its code. Shows what the iPhone sent, plus cards that arrived
/// through iCloud after that.
struct WatchWalletView: View {
    @Environment(PhoneLink.self) private var phone
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var stored: [Card]

    private var cards: [WatchCard] {
        let fromCloud = stored.smartSorted().map(WatchCard.init)
        guard let fromPhone = phone.cards else { return fromCloud }
        let known = Set(fromPhone.map(\.id))
        let since = phone.receivedAt ?? .distantPast
        let newer = stored.filter { !known.contains($0.id.uuidString) && $0.createdAt > since }.map(WatchCard.init)
        return fromPhone + newer
    }

    var body: some View {
        NavigationStack {
            let cards = cards
            Group {
                if cards.isEmpty {
                    ContentUnavailableView("Nog geen kaarten", systemImage: "wallet.pass",
                                           description: Text("Open Pasr op je iPhone. Je kaarten komen dan meteen hierheen."))
                } else {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let height = width / Brand.cardAspect
                        ScrollView {
                            // Each pass shows only its top strip, except the last one.
                            VStack(spacing: -(height - 40)) {
                                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                                    NavigationLink(value: card) {
                                        CardFaceView(appearance: card.appearance, showsCode: false, cornerRadius: 12)
                                            .frame(width: width, height: height)
                                    }
                                    .buttonStyle(.plain)
                                    .zIndex(Double(index))
                                }
                            }
                            .padding(.bottom, 12)
                        }
                    }
                }
            }
            .navigationTitle("Pasr")
            .navigationDestination(for: WatchCard.self) { card in
                WatchPassView(card: card, onShown: {
                    stored.first { $0.id.uuidString == card.id }?.markUsed()
                })
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { phone.requestCards() }
        }
    }
}

/// One pass with its code, as large as the screen allows. Tap to switch to the code alone on white.
struct WatchPassView: View {
    let card: WatchCard
    var onShown: () -> Void = {}
    @State private var codeOnly = false

    var body: some View {
        Group {
            if codeOnly {
                VStack(spacing: 6) {
                    BarcodeView(value: card.number, format: card.format, codeImage: card.code)
                        .frame(maxHeight: card.format.isLinear ? 80 : .infinity)
                    Text(card.appearance.groupedNumber)
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
                CardFaceView(appearance: card.appearance, revealed: true, cornerRadius: 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 2)
            }
        }
        .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { codeOnly.toggle() } }
        .navigationTitle(card.name)
        .onAppear(perform: onShown)
    }
}
