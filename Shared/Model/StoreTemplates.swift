import Foundation

/// A known Dutch store: name, website (for its logo), card colour and usual barcode type.
/// Colours approximate the store's house colour. Pasr bundles no logos; the device can fetch
/// the icon the store publishes on its own website (see LogoService).
struct StoreTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let domain: String
    let colorHex: String
    let format: BarcodeFormat
    var aliases: [String] = []
    var kind: CardKind = .loyalty

    /// Lowercased words used to recognise the store in screenshot text.
    var matchTerms: [String] { ([name] + aliases).map { $0.lowercased() } }
}

enum StoreTemplates {
    static let all: [StoreTemplate] = [
        // Supermarkten
        .init(id: "ah", name: "Albert Heijn", domain: "ah.nl", colorHex: "#00A0E2", format: .ean13, aliases: ["bonuskaart", "ah bonus"]),
        .init(id: "jumbo", name: "Jumbo", domain: "jumbo.com", colorHex: "#FFC917", format: .ean13, aliases: ["jumbo extra's"]),
        .init(id: "plus", name: "PLUS", domain: "plus.nl", colorHex: "#E2001A", format: .ean13),
        .init(id: "lidl", name: "Lidl Plus", domain: "lidl.nl", colorHex: "#0050AA", format: .qr, aliases: ["lidl"]),
        .init(id: "aldi", name: "ALDI", domain: "aldi.nl", colorHex: "#00005F", format: .ean13),
        .init(id: "dirk", name: "Dirk", domain: "dirk.nl", colorHex: "#E30613", format: .ean13),
        .init(id: "coop", name: "Coop", domain: "coop.nl", colorHex: "#F39200", format: .ean13),
        .init(id: "spar", name: "SPAR", domain: "spar.nl", colorHex: "#00843D", format: .ean13),
        .init(id: "vomar", name: "Vomar", domain: "vomar.nl", colorHex: "#E30613", format: .ean13),
        .init(id: "hoogvliet", name: "Hoogvliet", domain: "hoogvliet.com", colorHex: "#004A99", format: .ean13),
        .init(id: "dekamarkt", name: "DekaMarkt", domain: "dekamarkt.nl", colorHex: "#E2001A", format: .ean13),
        // Drogist en beauty
        .init(id: "kruidvat", name: "Kruidvat", domain: "kruidvat.nl", colorHex: "#E2001A", format: .ean13),
        .init(id: "etos", name: "Etos", domain: "etos.nl", colorHex: "#003B7E", format: .ean13),
        .init(id: "trekpleister", name: "Trekpleister", domain: "trekpleister.nl", colorHex: "#00A651", format: .ean13),
        .init(id: "douglas", name: "Douglas", domain: "douglas.nl", colorHex: "#1A1A1A", format: .ean13, aliases: ["beauty card"]),
        .init(id: "ici", name: "ICI PARIS XL", domain: "iciparisxl.nl", colorHex: "#111111", format: .ean13),
        .init(id: "rituals", name: "Rituals", domain: "rituals.com", colorHex: "#3B3A36", format: .code128),
        // Warenhuis en wonen
        .init(id: "hema", name: "HEMA", domain: "hema.nl", colorHex: "#E30613", format: .ean13, aliases: ["meer hema"]),
        .init(id: "action", name: "Action", domain: "action.com", colorHex: "#0071CE", format: .ean13),
        .init(id: "ikea", name: "IKEA Family", domain: "ikea.com", colorHex: "#0058A3", format: .code128, aliases: ["ikea"]),
        .init(id: "blokker", name: "Blokker", domain: "blokker.nl", colorHex: "#E3001B", format: .ean13),
        .init(id: "zeeman", name: "Zeeman", domain: "zeeman.com", colorHex: "#0060A9", format: .ean13),
        .init(id: "wibra", name: "Wibra", domain: "wibra.nl", colorHex: "#E4002B", format: .ean13),
        .init(id: "hunkemoller", name: "Hunkemöller", domain: "hunkemoller.nl", colorHex: "#1A1A1A", format: .ean13, aliases: ["hunkemoller"]),
        .init(id: "gall", name: "Gall & Gall", domain: "gall.nl", colorHex: "#7F1734", format: .ean13),
        // Klussen en tuin
        .init(id: "praxis", name: "Praxis", domain: "praxis.nl", colorHex: "#E30613", format: .ean13),
        .init(id: "gamma", name: "GAMMA", domain: "gamma.nl", colorHex: "#0050A0", format: .ean13),
        .init(id: "karwei", name: "Karwei", domain: "karwei.nl", colorHex: "#E95B0C", format: .ean13),
        .init(id: "hornbach", name: "HORNBACH", domain: "hornbach.nl", colorHex: "#F7941D", format: .ean13),
        .init(id: "intratuin", name: "Intratuin", domain: "intratuin.nl", colorHex: "#78B829", format: .ean13),
        // Elektronica, boeken, sport, speelgoed
        .init(id: "mediamarkt", name: "MediaMarkt", domain: "mediamarkt.nl", colorHex: "#DF0000", format: .ean13, aliases: ["mymediamarkt"]),
        .init(id: "decathlon", name: "Decathlon", domain: "decathlon.nl", colorHex: "#0082C3", format: .ean13),
        .init(id: "intertoys", name: "Intertoys", domain: "intertoys.nl", colorHex: "#E3000F", format: .ean13),
        .init(id: "bruna", name: "Bruna", domain: "bruna.nl", colorHex: "#F28C00", format: .ean13),
        .init(id: "primera", name: "Primera", domain: "primera.nl", colorHex: "#E2001A", format: .ean13),
        // Vrije tijd en onderweg
        .init(id: "anwb", name: "ANWB", domain: "anwb.nl", colorHex: "#FFCC00", format: .code128),
        .init(id: "pathe", name: "Pathé Unlimited", domain: "pathe.nl", colorHex: "#FFB800", format: .qr, aliases: ["pathé", "pathe"]),
        .init(id: "kinepolis", name: "Kinepolis", domain: "kinepolis.nl", colorHex: "#1D1D1B", format: .qr),
        .init(id: "bibliotheek", name: "Bibliotheek", domain: "bibliotheek.nl", colorHex: "#E6007E", format: .code39, aliases: ["bieb"]),
        .init(id: "shell", name: "Shell", domain: "shell.nl", colorHex: "#FFD500", format: .code128),
        // Cadeaukaarten
        .init(id: "bol", name: "bol cadeaukaart", domain: "bol.com", colorHex: "#0000A4", format: .code128, aliases: ["bol.com"], kind: .voucher),
        .init(id: "vvv", name: "VVV Cadeaukaart", domain: "vvvcadeaukaarten.nl", colorHex: "#00519E", format: .code128, aliases: ["vvv"], kind: .voucher),
        .init(id: "bioscoopbon", name: "Nationale Bioscoopbon", domain: "bioscoopbon.nl", colorHex: "#E2001A", format: .code128, aliases: ["bioscoopbon"], kind: .voucher),
    ]

    static func template(id: String?) -> StoreTemplate? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// Finds a store whose name or alias appears in recognised text.
    static func match(in text: String) -> StoreTemplate? {
        let haystack = text.lowercased()
        return all
            .flatMap { template in template.matchTerms.map { (template, $0) } }
            .filter { haystack.contains($0.1) }
            .max { $0.1.count < $1.1.count }?
            .0
    }

    /// "https://www.ah.nl/bonus" → "ah.nl"
    static func normalizedDomain(_ input: String?) -> String? {
        guard var text = input?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !text.isEmpty else { return nil }
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        guard text.contains("."), !text.contains(" ") else { return nil }
        return text
    }
}

extension Card {
    /// The website a logo can come from: the one typed on the card, or the store template's.
    var logoDomain: String? {
        StoreTemplates.normalizedDomain(website) ?? StoreTemplates.template(id: templateID)?.domain
    }
}
