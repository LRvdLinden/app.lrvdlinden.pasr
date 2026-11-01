import Foundation

/// A card as the iPhone hands it to the Apple Watch (via WatchConnectivity), complete with logo and
/// a rendered 2D code, so the Watch can show it straight away without waiting for iCloud.
struct WatchCard: Codable, Identifiable, Hashable {
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
    var logo: Data?
    var code: Data?

    var format: BarcodeFormat { BarcodeFormat(rawValue: formatRaw) ?? .code128 }
    var kind: CardKind { CardKind(rawValue: kindRaw) ?? .loyalty }

    var appearance: CardAppearance {
        CardAppearance(storeName: name, number: number, format: format, colorHex: colorHex, kind: kind,
                       isFavorite: isFavorite, logoData: logo, balance: balance, currencyCode: currencyCode,
                       expiresAt: expiresAt, isLocked: isLocked)
    }

    /// Without images: small enough for the application context, which arrives fastest.
    var withoutImages: WatchCard {
        var copy = self
        copy.logo = nil
        copy.code = nil
        return copy
    }
}

extension WatchCard {
    init(_ card: Card) {
        self.init(id: card.id.uuidString, name: card.storeName, colorHex: card.colorHex, number: card.number,
                  formatRaw: card.formatRaw, kindRaw: card.kindRaw, isFavorite: card.isFavorite,
                  isLocked: card.isLocked, balance: card.balance, currencyCode: card.currencyCode,
                  expiresAt: card.expiresAt, score: Card.score(card), logo: card.logoData, code: card.codeImage)
    }
}

enum WatchPayload {
    static func encode(_ cards: [WatchCard]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(cards)
    }

    static func decode(_ data: Data) -> [WatchCard]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([WatchCard].self, from: data)
    }
}
