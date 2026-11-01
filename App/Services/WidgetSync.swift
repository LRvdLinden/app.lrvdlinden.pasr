import Foundation
import WidgetKit

/// Keeps the widgets, and the Apple Watch, in step with the cards.
enum WidgetSync {
    @MainActor
    static func update(with cards: [Card]) {
        let (snapshot, logos) = cards.widgetSnapshot()
        WidgetStore.save(snapshot, logos: logos)
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        WatchLink.shared.send(cards)
        #endif
    }

    /// A short fingerprint of everything the widgets show, so they only reload when it changes.
    static func fingerprint(of cards: [Card]) -> String {
        cards.map { card in
            "\(card.id)|\(card.storeName)|\(card.number)|\(card.formatRaw)|\(card.colorHex)|\(card.isFavorite)|\(card.isLocked)|\(card.logoData?.count ?? 0)|\(card.balance ?? -1)|\(card.codeImage?.count ?? 0)|\(card.expiresAt?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: ";")
    }
}

/// Deep links from widgets: pasr://card/<id>
enum DeepLink {
    static func cardID(from url: URL) -> UUID? {
        guard url.scheme == "pasr", url.host() == "card" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
