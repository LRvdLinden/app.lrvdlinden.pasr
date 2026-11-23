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
    var e: Int?            // voucher or discount code expiry, seconds since 1970
    var x: CardDetails?    // ticket, abonnement, kortingscode (sinds 1.0.2; oudere versies negeren het)

    init(_ card: Card) {
        n = card.storeName
        c = card.number
        f = card.formatRaw
        h = card.colorHex
        k = card.kindRaw
        t = card.templateID
        w = card.website
        b = card.kind == .voucher ? card.balance : nil
        e = card.kind.hasExpiry ? card.expiresAt.map { Int($0.timeIntervalSince1970) } : nil
        var details = card.details
        details.captions = nil
        // een zakelijke stempelkaart deelt nooit de klantcode (zie CardShare.url: die gaat als join-link)
        details.issuer = nil
        details.businessCardId = nil
        details.memberCode = nil
        x = details.isEmpty ? nil : details
    }

    var format: BarcodeFormat { BarcodeFormat(rawValue: f) ?? .code128 }
    var kind: CardKind { CardKind(rawValue: k) ?? .loyalty }
    var expiresAt: Date? { e.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    var appearance: CardAppearance {
        var a = CardAppearance(storeName: n, number: c, format: format, colorHex: h, kind: kind,
                               balance: b, currencyCode: b == nil ? nil : "EUR", expiresAt: expiresAt)
            .with(details: x ?? CardDetails(), codeAsText: kind == .code && x?.codeAsBarcode != true)
        if kind == .voucher { a.storeCover = RemoteStores.cover(for: t) }
        return a
    }

    func makeCard() -> Card {
        let card = Card(storeName: n, number: c, format: format, kind: kind, colorHex: h)
        card.kindRaw = k
        if let x { card.details = x }
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
    /// Een zakelijke stempelkaart: de join-link van de zaak, zodat de ander een eigen kaart krijgt.
    static func url(for card: Card) -> URL? {
        let details = card.details
        if details.isBusiness, let id = details.businessCardId { return BusinessLink.url(for: id) }
        guard let data = try? JSONEncoder().encode(SharedCard(card)) else { return nil }
        return URL(string: webBase + "#" + base64URL(data))
    }

    /// Reads https://pasr.nl/kaart/#… and pasr://kaart#… links.
    static func decode(_ url: URL) -> SharedCard? {
        let isWeb = url.host() == "pasr.nl" && url.path().hasPrefix("/kaart")
        let isApp = url.scheme == "pasr" && url.host() == "kaart"
        guard isWeb || isApp, let fragment = url.fragment(), let data = fromBase64URL(fragment),
              let card = try? JSONDecoder().decode(SharedCard.self, from: data),
              !card.n.isEmpty, !card.c.isEmpty || card.kind == .stamps else { return nil }
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

/// Join-link van een zakelijke stempelkaart (Pasr voor ondernemers): https://pasr.nl/zakelijk/kaart/<business_card_id>/.
/// Opent Pasr als die er is (universal link), anders de eigen webpagina van de kaart (met de kaart als OG-afbeelding bij
/// delen) en de App Store-link. De oude vorm …/zakelijk/kaart/#<id> blijft werken.
enum BusinessLink {
    static let webBase = "https://pasr.nl/zakelijk/kaart/"

    static func url(for businessCardID: String) -> URL? { URL(string: webBase + businessCardID.lowercased() + "/") }

    /// Lidcode uit de browser: ?code=PZ… in de link ("Bewaar in Pasr" op pasr.nl, sinds build 43). De app neemt die
    /// over met pasr_business_claim, zodat de stempels uit de browser meegaan.
    static func memberCode(from url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let raw = items.first(where: { $0.name == "code" || $0.name == "lid" })?.value else { return nil }
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        return code.range(of: "^PZ([A-HJ-NP-Z2-9]{10}|[A-HJ-NP-Z2-9]{14})$", options: .regularExpression) != nil ? code : nil
    }

    /// Leest https://pasr.nl/zakelijk/kaart/<uuid>/ en de oude vorm https://pasr.nl/zakelijk/kaart/#<uuid> (ook www. en ?id=)
    /// en pasr://zakelijk/kaart#<uuid>.
    static func cardID(from url: URL) -> String? {
        let host = url.host()?.lowercased() ?? ""
        let isWeb = (host == "pasr.nl" || host == "www.pasr.nl") && url.path().hasPrefix("/zakelijk/kaart")
        let isApp = url.scheme == "pasr" && host == "zakelijk"
        guard isWeb || isApp else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
        let candidates = [url.fragment(), query, url.lastPathComponent].compactMap { $0 }
        for raw in candidates {
            let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased()
            if UUID(uuidString: value) != nil { return value }
        }
        return nil
    }
}
