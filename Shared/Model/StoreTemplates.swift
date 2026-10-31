import Foundation

/// A known Dutch store: name, website (for its logo), card colour and usual barcode type.
/// Colours approximate the store's house colour. Pasr bundles no logos; the device can fetch
/// the icon the store publishes on its own website (see LogoService).
struct StoreTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let domain: String
    let category: String
    let colorHex: String
    let format: BarcodeFormat
    var aliases: [String] = []
    var kind: CardKind = .loyalty

    /// Lowercased words used to recognise the store in screenshot text.
    var matchTerms: [String] { ([name] + aliases).map { $0.lowercased() } }
}

enum StoreTemplates {
    static let all: [StoreTemplate] = [
        // Supermarkt
        .init(id: "ah", name: "Albert Heijn", domain: "ah.nl", category: "Supermarkt", colorHex: "#00A0E2", format: .ean13, aliases: ["bonuskaart", "ah bonus"]),
        .init(id: "jumbo", name: "Jumbo", domain: "jumbo.com", category: "Supermarkt", colorHex: "#FFC917", format: .ean13, aliases: ["jumbo extra's"]),
        .init(id: "plus", name: "PLUS", domain: "plus.nl", category: "Supermarkt", colorHex: "#E2001A", format: .ean13),
        .init(id: "lidl", name: "Lidl Plus", domain: "lidl.nl", category: "Supermarkt", colorHex: "#0050AA", format: .qr, aliases: ["lidl"]),
        .init(id: "aldi", name: "ALDI", domain: "aldi.nl", category: "Supermarkt", colorHex: "#00005F", format: .ean13),
        .init(id: "dirk", name: "Dirk", domain: "dirk.nl", category: "Supermarkt", colorHex: "#E30613", format: .ean13),
        .init(id: "coop", name: "Coop", domain: "coop.nl", category: "Supermarkt", colorHex: "#F39200", format: .ean13),
        .init(id: "spar", name: "SPAR", domain: "spar.nl", category: "Supermarkt", colorHex: "#00843D", format: .ean13),
        .init(id: "vomar", name: "Vomar", domain: "vomar.nl", category: "Supermarkt", colorHex: "#E30613", format: .ean13),
        .init(id: "hoogvliet", name: "Hoogvliet", domain: "hoogvliet.com", category: "Supermarkt", colorHex: "#004A99", format: .ean13),
        .init(id: "dekamarkt", name: "DekaMarkt", domain: "dekamarkt.nl", category: "Supermarkt", colorHex: "#E2001A", format: .ean13),
        .init(id: "poiesz", name: "Poiesz", domain: "poiesz-supermarkten.nl", category: "Supermarkt", colorHex: "#E30613", format: .ean13),
        .init(id: "janlinders", name: "Jan Linders", domain: "janlinders.nl", category: "Supermarkt", colorHex: "#E2001A", format: .ean13),
        .init(id: "boni", name: "Boni", domain: "boni.nl", category: "Supermarkt", colorHex: "#E30613", format: .ean13),
        .init(id: "nettorama", name: "Nettorama", domain: "nettorama.nl", category: "Supermarkt", colorHex: "#004C97", format: .ean13),
        .init(id: "ekoplaza", name: "Ekoplaza", domain: "ekoplaza.nl", category: "Supermarkt", colorHex: "#5A8C2B", format: .ean13),
        .init(id: "boons", name: "Boon's Markt", domain: "boonsmarkt.nl", category: "Supermarkt", colorHex: "#E2001A", format: .ean13),
        .init(id: "makro", name: "Makro", domain: "makro.nl", category: "Supermarkt", colorHex: "#003D7C", format: .code128, aliases: ["makro pas"]),
        .init(id: "sligro", name: "Sligro", domain: "sligro.nl", category: "Supermarkt", colorHex: "#E30613", format: .code128),
        .init(id: "hanos", name: "HANOS", domain: "hanos.nl", category: "Supermarkt", colorHex: "#1A1A1A", format: .code128),
        // Drogist en beauty
        .init(id: "kruidvat", name: "Kruidvat", domain: "kruidvat.nl", category: "Drogist en beauty", colorHex: "#E2001A", format: .ean13),
        .init(id: "etos", name: "Etos", domain: "etos.nl", category: "Drogist en beauty", colorHex: "#003B7E", format: .ean13),
        .init(id: "trekpleister", name: "Trekpleister", domain: "trekpleister.nl", category: "Drogist en beauty", colorHex: "#00A651", format: .ean13),
        .init(id: "da", name: "DA Drogist", domain: "da.nl", category: "Drogist en beauty", colorHex: "#E30613", format: .ean13),
        .init(id: "hollandbarrett", name: "Holland & Barrett", domain: "hollandandbarrett.nl", category: "Drogist en beauty", colorHex: "#00563F", format: .ean13, aliases: ["holland and barrett"]),
        .init(id: "douglas", name: "Douglas", domain: "douglas.nl", category: "Drogist en beauty", colorHex: "#1A1A1A", format: .ean13, aliases: ["beauty card"]),
        .init(id: "ici", name: "ICI PARIS XL", domain: "iciparisxl.nl", category: "Drogist en beauty", colorHex: "#111111", format: .ean13),
        .init(id: "rituals", name: "Rituals", domain: "rituals.com", category: "Drogist en beauty", colorHex: "#3B3A36", format: .code128),
        .init(id: "bodyshop", name: "The Body Shop", domain: "thebodyshop.com", category: "Drogist en beauty", colorHex: "#004236", format: .ean13, aliases: ["body shop"]),
        .init(id: "yvesrocher", name: "Yves Rocher", domain: "yves-rocher.nl", category: "Drogist en beauty", colorHex: "#2E5E3E", format: .ean13),
        .init(id: "lucardi", name: "Lucardi", domain: "lucardi.nl", category: "Drogist en beauty", colorHex: "#1A1A1A", format: .ean13),
        // Warenhuis en wonen
        .init(id: "hema", name: "HEMA", domain: "hema.nl", category: "Warenhuis en wonen", colorHex: "#E30613", format: .ean13, aliases: ["meer hema"]),
        .init(id: "action", name: "Action", domain: "action.com", category: "Warenhuis en wonen", colorHex: "#0071CE", format: .ean13),
        .init(id: "bijenkorf", name: "de Bijenkorf", domain: "debijenkorf.nl", category: "Warenhuis en wonen", colorHex: "#1A1A1A", format: .code128, aliases: ["bijenkorf"]),
        .init(id: "ikea", name: "IKEA Family", domain: "ikea.com", category: "Warenhuis en wonen", colorHex: "#0058A3", format: .code128, aliases: ["ikea"]),
        .init(id: "blokker", name: "Blokker", domain: "blokker.nl", category: "Warenhuis en wonen", colorHex: "#E3001B", format: .ean13),
        .init(id: "xenos", name: "Xenos", domain: "xenos.nl", category: "Warenhuis en wonen", colorHex: "#E30613", format: .ean13),
        .init(id: "leenbakker", name: "Leen Bakker", domain: "leenbakker.nl", category: "Warenhuis en wonen", colorHex: "#E30613", format: .ean13),
        .init(id: "kwantum", name: "Kwantum", domain: "kwantum.nl", category: "Warenhuis en wonen", colorHex: "#FFD200", format: .ean13),
        .init(id: "jysk", name: "JYSK", domain: "jysk.nl", category: "Warenhuis en wonen", colorHex: "#003F7D", format: .ean13),
        .init(id: "zeeman", name: "Zeeman", domain: "zeeman.com", category: "Warenhuis en wonen", colorHex: "#0060A9", format: .ean13),
        .init(id: "wibra", name: "Wibra", domain: "wibra.nl", category: "Warenhuis en wonen", colorHex: "#E4002B", format: .ean13),
        .init(id: "bigbazar", name: "Big Bazar", domain: "bigbazar.eu", category: "Warenhuis en wonen", colorHex: "#E30613", format: .ean13),
        .init(id: "sostrene", name: "Søstrene Grene", domain: "sostrenegrene.com", category: "Warenhuis en wonen", colorHex: "#1A1A1A", format: .ean13, aliases: ["sostrene grene"]),
        // Mode en schoenen
        .init(id: "hm", name: "H&M", domain: "hm.com", category: "Mode en schoenen", colorHex: "#E50010", format: .code128, aliases: ["h&m member"]),
        .init(id: "ca", name: "C&A", domain: "c-and-a.com", category: "Mode en schoenen", colorHex: "#1D3C8F", format: .ean13, aliases: ["c&a"]),
        .init(id: "wefashion", name: "WE Fashion", domain: "wefashion.nl", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "shoeby", name: "Shoeby", domain: "shoeby.nl", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "hunkemoller", name: "Hunkemöller", domain: "hunkemoller.nl", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13, aliases: ["hunkemoller"]),
        .init(id: "missetam", name: "Miss Etam", domain: "missetam.nl", category: "Mode en schoenen", colorHex: "#C8102E", format: .ean13),
        .init(id: "only", name: "ONLY", domain: "only.com", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "esprit", name: "Esprit", domain: "esprit.nl", category: "Mode en schoenen", colorHex: "#E30613", format: .ean13),
        .init(id: "vanharen", name: "vanHaren", domain: "vanharen.nl", category: "Mode en schoenen", colorHex: "#E30613", format: .ean13, aliases: ["van haren"]),
        .init(id: "scapino", name: "Scapino", domain: "scapino.nl", category: "Mode en schoenen", colorHex: "#E2001A", format: .ean13),
        .init(id: "nelson", name: "Nelson", domain: "nelson.nl", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "ziengs", name: "Ziengs", domain: "ziengs.nl", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "bristol", name: "Bristol", domain: "bristol.nl", category: "Mode en schoenen", colorHex: "#E30613", format: .ean13),
        .init(id: "terstal", name: "Ter Stal", domain: "terstal.nl", category: "Mode en schoenen", colorHex: "#E30613", format: .ean13, aliases: ["terstal"]),
        // Klussen, tuin en dieren
        .init(id: "praxis", name: "Praxis", domain: "praxis.nl", category: "Klussen, tuin en dieren", colorHex: "#E30613", format: .ean13),
        .init(id: "gamma", name: "GAMMA", domain: "gamma.nl", category: "Klussen, tuin en dieren", colorHex: "#0050A0", format: .ean13),
        .init(id: "karwei", name: "Karwei", domain: "karwei.nl", category: "Klussen, tuin en dieren", colorHex: "#E95B0C", format: .ean13),
        .init(id: "hornbach", name: "HORNBACH", domain: "hornbach.nl", category: "Klussen, tuin en dieren", colorHex: "#F7941D", format: .ean13),
        .init(id: "hubo", name: "Hubo", domain: "hubo.nl", category: "Klussen, tuin en dieren", colorHex: "#E30613", format: .ean13),
        .init(id: "bauhaus", name: "BAUHAUS", domain: "bauhaus.nl", category: "Klussen, tuin en dieren", colorHex: "#E30613", format: .ean13),
        .init(id: "intratuin", name: "Intratuin", domain: "intratuin.nl", category: "Klussen, tuin en dieren", colorHex: "#78B829", format: .ean13),
        .init(id: "groenrijk", name: "GroenRijk", domain: "groenrijk.nl", category: "Klussen, tuin en dieren", colorHex: "#5A9E2F", format: .ean13),
        .init(id: "welkoop", name: "Welkoop", domain: "welkoop.nl", category: "Klussen, tuin en dieren", colorHex: "#00843D", format: .ean13),
        .init(id: "petsplace", name: "Pets Place", domain: "petsplace.nl", category: "Klussen, tuin en dieren", colorHex: "#E2001A", format: .ean13),
        .init(id: "jumper", name: "Jumper", domain: "jumper.nl", category: "Klussen, tuin en dieren", colorHex: "#0072BC", format: .ean13),
        .init(id: "boerenbond", name: "Boerenbond", domain: "boerenbond.nl", category: "Klussen, tuin en dieren", colorHex: "#00843D", format: .ean13),
        // Elektronica, boeken en speelgoed
        .init(id: "mediamarkt", name: "MediaMarkt", domain: "mediamarkt.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#DF0000", format: .ean13, aliases: ["mymediamarkt"]),
        .init(id: "expert", name: "Expert", domain: "expert.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E30613", format: .ean13),
        .init(id: "bruna", name: "Bruna", domain: "bruna.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#F28C00", format: .ean13),
        .init(id: "primera", name: "Primera", domain: "primera.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E2001A", format: .ean13),
        .init(id: "ako", name: "AKO", domain: "ako.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E30613", format: .ean13),
        .init(id: "readshop", name: "The Read Shop", domain: "readshop.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E30613", format: .ean13, aliases: ["read shop"]),
        .init(id: "libris", name: "Libris", domain: "libris.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "intertoys", name: "Intertoys", domain: "intertoys.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E3000F", format: .ean13),
        .init(id: "top1toys", name: "Top1Toys", domain: "top1toys.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E30613", format: .ean13),
        // Sport en fitness
        .init(id: "decathlon", name: "Decathlon", domain: "decathlon.nl", category: "Sport en fitness", colorHex: "#0082C3", format: .ean13),
        .init(id: "intersport", name: "Intersport", domain: "intersport.nl", category: "Sport en fitness", colorHex: "#003DA5", format: .ean13),
        .init(id: "perrysport", name: "Perry Sport", domain: "perrysport.nl", category: "Sport en fitness", colorHex: "#E30613", format: .ean13),
        .init(id: "bever", name: "Bever", domain: "bever.nl", category: "Sport en fitness", colorHex: "#004F2D", format: .ean13),
        .init(id: "basicfit", name: "Basic-Fit", domain: "basic-fit.com", category: "Sport en fitness", colorHex: "#FF7900", format: .qr, aliases: ["basic fit"]),
        .init(id: "sportcity", name: "SportCity", domain: "sportcity.nl", category: "Sport en fitness", colorHex: "#E30613", format: .qr),
        .init(id: "anytime", name: "Anytime Fitness", domain: "anytimefitness.nl", category: "Sport en fitness", colorHex: "#5E2D91", format: .code128),
        // Tanken en sparen
        .init(id: "airmiles", name: "Air Miles", domain: "airmiles.nl", category: "Tanken en sparen", colorHex: "#0033A0", format: .ean13, aliases: ["air miles", "airmiles"]),
        .init(id: "shell", name: "Shell", domain: "shell.nl", category: "Tanken en sparen", colorHex: "#FFD500", format: .code128, aliases: ["shell go+", "shellgo"]),
        .init(id: "bp", name: "BP", domain: "bp.com", category: "Tanken en sparen", colorHex: "#007F00", format: .code128),
        .init(id: "esso", name: "Esso", domain: "esso.nl", category: "Tanken en sparen", colorHex: "#D8282F", format: .code128),
        .init(id: "total", name: "TotalEnergies", domain: "totalenergies.nl", category: "Tanken en sparen", colorHex: "#E30613", format: .code128, aliases: ["total"]),
        .init(id: "tango", name: "Tango", domain: "tango.nl", category: "Tanken en sparen", colorHex: "#E30613", format: .code128),
        .init(id: "tinq", name: "TinQ", domain: "tinq.nl", category: "Tanken en sparen", colorHex: "#00A0E2", format: .code128),
        .init(id: "texaco", name: "Texaco", domain: "texaco.nl", category: "Tanken en sparen", colorHex: "#E30613", format: .code128),
        // Uitgaan en vrije tijd
        .init(id: "pathe", name: "Pathé Unlimited", domain: "pathe.nl", category: "Uitgaan en vrije tijd", colorHex: "#FFB800", format: .qr, aliases: ["pathé", "pathe"]),
        .init(id: "vue", name: "Vue", domain: "vuecinemas.nl", category: "Uitgaan en vrije tijd", colorHex: "#1A1A1A", format: .qr),
        .init(id: "kinepolis", name: "Kinepolis", domain: "kinepolis.nl", category: "Uitgaan en vrije tijd", colorHex: "#1D1D1B", format: .qr),
        .init(id: "museumkaart", name: "Museumkaart", domain: "museum.nl", category: "Uitgaan en vrije tijd", colorHex: "#E30613", format: .code128, aliases: ["museum"]),
        .init(id: "cjp", name: "CJP", domain: "cjp.nl", category: "Uitgaan en vrije tijd", colorHex: "#FF4F00", format: .code128),
        .init(id: "bibliotheek", name: "Bibliotheek", domain: "bibliotheek.nl", category: "Uitgaan en vrije tijd", colorHex: "#E6007E", format: .code39, aliases: ["bieb"]),
        .init(id: "anwb", name: "ANWB", domain: "anwb.nl", category: "Uitgaan en vrije tijd", colorHex: "#FFCC00", format: .code128),
        .init(id: "starbucks", name: "Starbucks", domain: "starbucks.nl", category: "Uitgaan en vrije tijd", colorHex: "#00704A", format: .qr),
        // Optiek en zorg
        .init(id: "pearle", name: "Pearle", domain: "pearle.nl", category: "Optiek en zorg", colorHex: "#00843D", format: .ean13),
        .init(id: "hansanders", name: "Hans Anders", domain: "hansanders.nl", category: "Optiek en zorg", colorHex: "#E30613", format: .ean13),
        .init(id: "specsavers", name: "Specsavers", domain: "specsavers.nl", category: "Optiek en zorg", colorHex: "#00843D", format: .ean13),
        .init(id: "benu", name: "BENU Apotheek", domain: "benu.nl", category: "Optiek en zorg", colorHex: "#E30613", format: .code128, aliases: ["benu"]),
        // Drank en eten
        .init(id: "gall", name: "Gall & Gall", domain: "gall.nl", category: "Drank en eten", colorHex: "#7F1734", format: .ean13),
        .init(id: "mitra", name: "Mitra", domain: "mitra.nl", category: "Drank en eten", colorHex: "#E30613", format: .ean13),
        .init(id: "smullers", name: "Smullers", domain: "smullers.nl", category: "Drank en eten", colorHex: "#E30613", format: .qr),
        // Cadeaukaarten
        .init(id: "bol", name: "bol cadeaukaart", domain: "bol.com", category: "Cadeaukaarten", colorHex: "#0000A4", format: .code128, aliases: ["bol.com"], kind: .voucher),
        .init(id: "vvv", name: "VVV Cadeaukaart", domain: "vvvcadeaukaarten.nl", category: "Cadeaukaarten", colorHex: "#00519E", format: .code128, aliases: ["vvv"], kind: .voucher),
        .init(id: "bioscoopbon", name: "Nationale Bioscoopbon", domain: "bioscoopbon.nl", category: "Cadeaukaarten", colorHex: "#E2001A", format: .code128, aliases: ["bioscoopbon"], kind: .voucher),
        .init(id: "hemacadeau", name: "HEMA cadeaukaart", domain: "hema.nl", category: "Cadeaukaarten", colorHex: "#E30613", format: .code128, kind: .voucher),
        .init(id: "ikeacadeau", name: "IKEA cadeaukaart", domain: "ikea.com", category: "Cadeaukaarten", colorHex: "#0058A3", format: .code128, kind: .voucher),
        .init(id: "boekenbon", name: "Boekenbon", domain: "boekenbon.nl", category: "Cadeaukaarten", colorHex: "#1A1A1A", format: .code128, kind: .voucher),
        .init(id: "intertoyscadeau", name: "Intertoys cadeaukaart", domain: "intertoys.nl", category: "Cadeaukaarten", colorHex: "#E3000F", format: .code128, kind: .voucher),
        .init(id: "ahcadeau", name: "AH Cadeaukaart", domain: "ah.nl", category: "Cadeaukaarten", colorHex: "#00A0E2", format: .code128, kind: .voucher),
    ]

    /// Category names in display order.
    static let categories: [String] = {
        var seen: [String] = []
        for t in all where !seen.contains(t.category) { seen.append(t.category) }
        return seen
    }()

    static func template(id: String?) -> StoreTemplate? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// Finds a store whose name or alias appears as whole words in recognised text.
    static func match(in text: String) -> StoreTemplate? {
        let haystack = text.lowercased()
        return all
            .flatMap { template in template.matchTerms.map { (template, $0) } }
            .filter { term in
                let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: term.1) + "(?![\\p{L}\\p{N}])"
                return haystack.range(of: pattern, options: .regularExpression) != nil
            }
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
