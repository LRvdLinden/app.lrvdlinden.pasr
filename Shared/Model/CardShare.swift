import Foundation

/// A card as it travels in a share link. Everything sits in the part after `#`,
/// which browsers never send to a server: pasr.nl only serves the page, the card data stays
/// between the two people. Logos and photos are left out; the receiver fetches the logo itself.
struct SharedCard: Codable, Equatable {
    var v = 1
    var n: String          // store name
    var c: String          // card number / code value
    var f: String          // barcode format
    var h: String          // colour hex
    var k: String          // kind
    var t: String?         // store template id
    var w: String?         // website for the logo
    var b: Double?         // voucher balance
    var e: Int?            // voucher expiry, seconds since 1970

    init(_ card: Card) {
        n = card.storeName
        c = card.number
        f = card.formatRaw
        h = card.colorHex
        k = card.kindRaw
        t = card.templateID
        w = card.website
        b = card.kind == .voucher ? card.balance : nil
        e = card.kind == .voucher ? card.expiresAt.map { Int($0.timeIntervalSince1970) } : nil
    }

    var format: BarcodeFormat { BarcodeFormat(rawValue: f) ?? .code128 }
    var kind: CardKind { CardKind(rawValue: k) ?? .loyalty }
    var expiresAt: Date? { e.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    var appearance: CardAppearance {
        CardAppearance(storeName: n, number: c, format: format, colorHex: h, kind: kind,
                       balance: b, currencyCode: b == nil ? nil : "EUR", expiresAt: expiresAt)
    }

    func makeCard() -> Card {
        let card = Card(storeName: n, number: c, format: format, kind: kind, colorHex: h)
        card.templateID = t
        card.website = w
        card.balance = b
        card.currencyCode = b == nil ? nil : "EUR"
        card.expiresAt = expiresAt
        return card
    }
}

enum CardShare {
    static let webBase = "https://pasr.nl/kaart/"

    /// https://pasr.nl/kaart/#<data> — opens Pasr when installed, otherwise shows the card on the web.
    static func url(for card: Card) -> URL? {
        guard let data = try? JSONEncoder().encode(SharedCard(card)) else { return nil }
        return URL(string: webBase + "#" + base64URL(data))
    }

    /// Reads https://pasr.nl/kaart/#… and pasr://kaart#… links.
    static func decode(_ url: URL) -> SharedCard? {
        let isWeb = url.host() == "pasr.nl" && url.path().hasPrefix("/kaart")
        let isApp = url.scheme == "pasr" && url.host() == "kaart"
        guard isWeb || isApp, let fragment = url.fragment(), let data = fromBase64URL(fragment),
              let card = try? JSONDecoder().decode(SharedCard.self, from: data),
              !card.n.isEmpty, !card.c.isEmpty else { return nil }
        return card
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func fromBase64URL(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}
