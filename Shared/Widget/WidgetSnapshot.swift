import Foundation

/// What the widgets know about a card. The app writes these to the shared App Group
/// whenever cards change; the widget extension only reads them.
struct WidgetCard: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var colorHex: String
    var number: String
    var formatRaw: String
    var kindRaw: String
    var isFavorite: Bool
    var isLocked: Bool
    var balance: Double?
    var currencyCode: String?
    var expiresAt: Date?
    var score: Double
    /// Website of the store, to draw its logo the right way (see StoreLogoStyles).
    var logoDomain: String? = nil

    var format: BarcodeFormat { BarcodeFormat(rawValue: formatRaw) ?? .code128 }
    var kind: CardKind { CardKind(rawValue: kindRaw) ?? .loyalty }
    var url: URL { URL(string: "pasr://card/\(id)")! }

    var logoData: Data? { try? Data(contentsOf: WidgetStore.logoURL(for: id)) }

    var appearance: CardAppearance {
        CardAppearance(storeName: name, number: number, format: format, colorHex: colorHex, kind: kind,
                       isFavorite: isFavorite, logoData: logoData, balance: balance, currencyCode: currencyCode,
                       expiresAt: expiresAt, isLocked: isLocked, logoStyle: StoreLogoStyles.style(for: logoDomain))
    }

    var monogram: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    static let preview: [WidgetCard] = [
        WidgetCard(id: "a", name: "Albert Heijn", colorHex: "#00A0E2", number: "2620123456782", formatRaw: "ean13",
                   kindRaw: "loyalty", isFavorite: true, isLocked: false, score: 9),
        WidgetCard(id: "b", name: "HEMA", colorHex: "#E30613", number: "8712345678906", formatRaw: "ean13",
                   kindRaw: "loyalty", isFavorite: true, isLocked: false, score: 5),
        WidgetCard(id: "c", name: "Kruidvat", colorHex: "#E2001A", number: "2600000000002", formatRaw: "ean13",
                   kindRaw: "loyalty", isFavorite: true, isLocked: false, score: 4),
        WidgetCard(id: "d", name: "IKEA Family", colorHex: "#0058A3", number: "6275980123456789", formatRaw: "code128",
                   kindRaw: "loyalty", isFavorite: true, isLocked: false, score: 2),
    ]
}

enum WidgetStore {
    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PasrStore.appGroup)?
            .appending(path: "Widgets", directoryHint: .isDirectory)
    }

    static var cardsURL: URL? { folder?.appending(path: "cards.json") }

    static func logoURL(for id: String) -> URL {
        (folder ?? FileManager.default.temporaryDirectory).appending(path: "logo-\(id).png")
    }

    /// All cards, best first: favourites, then the ones used most.
    static func load() -> [WidgetCard] {
        guard let url = cardsURL, let data = try? Data(contentsOf: url),
              let cards = try? JSONDecoder().decode([WidgetCard].self, from: data) else { return [] }
        return cards
    }

    /// Favourites; if there are none yet, the most-used cards.
    static func favourites() -> [WidgetCard] {
        let all = load()
        let favs = all.filter(\.isFavorite)
        return favs.isEmpty ? all : favs
    }

    static func save(_ cards: [WidgetCard], logos: [String: Data]) {
        guard let folder, let url = cardsURL else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cards) { try? data.write(to: url, options: .atomic) }
        let keep = Set(cards.map(\.id))
        for (id, logo) in logos where keep.contains(id) {
            try? logo.write(to: logoURL(for: id), options: .atomic)
        }
        // Remove logos of cards that are gone or no longer have one.
        if let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for file in files where file.hasPrefix("logo-") {
                let id = String(file.dropFirst(5).dropLast(4))
                if logos[id] == nil { try? FileManager.default.removeItem(at: folder.appending(path: file)) }
            }
        }
    }
}

extension Array where Element == Card {
    /// The snapshot the widgets read, in smart order.
    func widgetSnapshot() -> ([WidgetCard], [String: Data]) {
        var logos: [String: Data] = [:]
        let cards = filter { $0.deletedAt == nil }.smartSorted().map { card -> WidgetCard in
            if let logo = card.logoData { logos[card.id.uuidString] = logo }
            return WidgetCard(id: card.id.uuidString, name: card.storeName, colorHex: card.colorHex,
                              number: card.number, formatRaw: card.formatRaw, kindRaw: card.kindRaw,
                              isFavorite: card.isFavorite, isLocked: card.isLocked, balance: card.balance,
                              currencyCode: card.currencyCode, expiresAt: card.expiresAt, score: Card.score(card),
                              logoDomain: card.logoFromWebsite ? card.logoDomain : nil)
        }
        return (cards, logos)
    }
}
