import Foundation

/// A known store: name, card colour and the barcode type it usually uses.
/// Colours are approximations of the store's house colour; no logos are bundled.
struct StoreTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: String
    let format: BarcodeFormat
    var aliases: [String] = []
    var kind: CardKind = .loyalty

    /// Lowercased words used to recognise the store in screenshot text.
    var matchTerms: [String] { ([name] + aliases).map { $0.lowercased() } }
}

enum StoreTemplates {
    static let all: [StoreTemplate] = [
        .init(id: "ah", name: "Albert Heijn", colorHex: "#00A0E2", format: .ean13, aliases: ["bonuskaart", "ah bonus"]),
        .init(id: "jumbo", name: "Jumbo", colorHex: "#FFC917", format: .ean13, aliases: ["jumbo extra's"]),
        .init(id: "plus", name: "PLUS", colorHex: "#E2001A", format: .ean13),
        .init(id: "lidl", name: "Lidl Plus", colorHex: "#0050AA", format: .qr, aliases: ["lidl"]),
        .init(id: "aldi", name: "ALDI", colorHex: "#00005F", format: .ean13),
        .init(id: "dirk", name: "Dirk", colorHex: "#E30613", format: .ean13),
        .init(id: "hema", name: "HEMA", colorHex: "#E30613", format: .ean13, aliases: ["meer hema"]),
        .init(id: "kruidvat", name: "Kruidvat", colorHex: "#E2001A", format: .ean13),
        .init(id: "etos", name: "Etos", colorHex: "#003B7E", format: .ean13),
        .init(id: "trekpleister", name: "Trekpleister", colorHex: "#00A651", format: .ean13),
        .init(id: "douglas", name: "Douglas", colorHex: "#1A1A1A", format: .ean13, aliases: ["beauty card"]),
        .init(id: "ici", name: "ICI PARIS XL", colorHex: "#111111", format: .ean13),
        .init(id: "rituals", name: "Rituals", colorHex: "#3B3A36", format: .code128),
        .init(id: "action", name: "Action", colorHex: "#0071CE", format: .ean13),
        .init(id: "ikea", name: "IKEA Family", colorHex: "#0058A3", format: .code128, aliases: ["ikea"]),
        .init(id: "praxis", name: "Praxis", colorHex: "#E30613", format: .ean13),
        .init(id: "gamma", name: "GAMMA", colorHex: "#0050A0", format: .ean13),
        .init(id: "karwei", name: "Karwei", colorHex: "#E95B0C", format: .ean13),
        .init(id: "hornbach", name: "HORNBACH", colorHex: "#F7941D", format: .ean13),
        .init(id: "intratuin", name: "Intratuin", colorHex: "#78B829", format: .ean13),
        .init(id: "decathlon", name: "Decathlon", colorHex: "#0082C3", format: .ean13),
        .init(id: "mediamarkt", name: "MediaMarkt", colorHex: "#DF0000", format: .ean13, aliases: ["myMediaMarkt"]),
        .init(id: "intertoys", name: "Intertoys", colorHex: "#E3000F", format: .ean13),
        .init(id: "bruna", name: "Bruna", colorHex: "#F28C00", format: .ean13),
        .init(id: "primera", name: "Primera", colorHex: "#E2001A", format: .ean13),
        .init(id: "blokker", name: "Blokker", colorHex: "#E3001B", format: .ean13),
        .init(id: "zeeman", name: "Zeeman", colorHex: "#0060A9", format: .ean13),
        .init(id: "wibra", name: "Wibra", colorHex: "#E4002B", format: .ean13),
        .init(id: "anwb", name: "ANWB", colorHex: "#FFCC00", format: .code128),
        .init(id: "pathe", name: "Pathé Unlimited", colorHex: "#FFB800", format: .qr, aliases: ["pathé", "pathe"]),
        .init(id: "bibliotheek", name: "Bibliotheek", colorHex: "#E6007E", format: .code39, aliases: ["bieb"]),
        .init(id: "shell", name: "Shell", colorHex: "#FFD500", format: .code128),
        .init(id: "delhaize", name: "Delhaize", colorHex: "#E2001A", format: .ean13, aliases: ["superplus"]),
        .init(id: "colruyt", name: "Colruyt", colorHex: "#EE7203", format: .ean13, aliases: ["colruyt xtra"]),
        .init(id: "carrefour", name: "Carrefour", colorHex: "#004E9F", format: .ean13, aliases: ["bonus card"]),
        .init(id: "bol", name: "bol cadeaukaart", colorHex: "#0000A4", format: .code128, aliases: ["bol.com"], kind: .voucher),
        .init(id: "vvv", name: "VVV Cadeaukaart", colorHex: "#00519E", format: .code128, aliases: ["vvv"], kind: .voucher),
        .init(id: "giftforyou", name: "Nationale Cadeaukaart", colorHex: "#E6007E", format: .code128, kind: .voucher),
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
}
