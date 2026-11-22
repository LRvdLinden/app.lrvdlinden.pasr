import Foundation
import WidgetKit

/// Keeps the widgets, and the Apple Watch, in step with the cards.
enum WidgetSync {
    @MainActor
    static func update(with cards: [Card]) {
        let order = CardOrder.current
        var distances: [UUID: Double] = [:]
        if order.usesLocation, let here = NearbyStores.shared.lastLocation {
            distances = NearbyStores.shared.knownDistances(for: cards, from: here)
        }
        let (snapshot, logos) = cards.widgetSnapshot(order: order, distances: distances)
        WidgetStore.save(snapshot, logos: logos)
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        WatchLink.shared.send(cards, order: order, distances: distances)
        #endif
        Task {
            await Reminders.rescheduleVouchers(cards)
            await Birthday.reschedule(cards)
        }
        StorePush.cardsChanged(cards)
    }

    /// A short fingerprint of everything the widgets show, so they only reload when it changes.
    static func fingerprint(of cards: [Card]) -> String {
        let order = CardOrder.current
        let byUse = order == .used || order == .nearUsed
        return order.rawValue + ";" + cards.map { card in
            "\(card.id)|\(card.storeName)|\(card.number)|\(card.formatRaw)|\(card.colorHex)|\(card.isFavorite)|\(card.isLocked)|\(card.logoData?.count ?? 0)|\(card.balance ?? -1)|\(card.codeImage?.count ?? 0)|\(card.expiresAt?.timeIntervalSince1970 ?? 0)|\(card.kindRaw)|\(card.detailsData?.hashValue ?? 0)|\(byUse ? card.useCount : 0)|\(card.coverPhoto?.count ?? 0)|\(card.storeCover != nil ? RemoteStores.coverVersion(for: card.templateID) ?? "" : "")"
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
