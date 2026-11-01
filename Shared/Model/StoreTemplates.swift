import Foundation

/// A known Dutch store: name, website (for its logo), card colour and usual barcode type.
/// Colours approximate the store's house colour. Logos live in Shared/StoreLogos/<domain>.png
/// (see tools/fetch_logos.py and LogoService).
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
        // Uitbreiding build 4
        .init(id: "picnic", name: "Picnic", domain: "picnic.app", category: "Supermarkt", colorHex: "#E1171E", format: .qr),
        .init(id: "crisp", name: "Crisp", domain: "crisp.nl", category: "Supermarkt", colorHex: "#1E3D2F", format: .qr),
        .init(id: "deen", name: "Deen", domain: "deen.nl", category: "Supermarkt", colorHex: "#E30613", format: .ean13),
        .init(id: "mcd", name: "MCD Supermarkt", domain: "mcd-supermarkt.nl", category: "Supermarkt", colorHex: "#E30613", format: .ean13, aliases: ["mcd"]),
        .init(id: "lekkerland", name: "Lekkerland", domain: "lekkerland.nl", category: "Supermarkt", colorHex: "#E30613", format: .code128),
        .init(id: "albertheijnto", name: "AH to go", domain: "ah.nl", category: "Supermarkt", colorHex: "#00A0E2", format: .ean13, aliases: ["ah to go"]),
        .init(id: "jumbofoodmarkt", name: "Jumbo Foodmarkt", domain: "jumbo.com", category: "Supermarkt", colorHex: "#FFC917", format: .ean13),
        .init(id: "amazingoriental", name: "Amazing Oriental", domain: "amazingoriental.nl", category: "Supermarkt", colorHex: "#C8102E", format: .ean13),
        .init(id: "tanger", name: "Tanger Supermarkt", domain: "tangersupermarkt.nl", category: "Supermarkt", colorHex: "#00843D", format: .ean13, aliases: ["tanger"]),
        .init(id: "marqt", name: "Marqt", domain: "marqt.com", category: "Supermarkt", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "odin", name: "Odin", domain: "odin.nl", category: "Supermarkt", colorHex: "#5A8C2B", format: .ean13),
        .init(id: "natuurwinkel", name: "De Natuurwinkel", domain: "natuurwinkel.nl", category: "Supermarkt", colorHex: "#5A8C2B", format: .ean13, aliases: ["natuurwinkel"]),
        .init(id: "costco", name: "Costco", domain: "costco.nl", category: "Supermarkt", colorHex: "#E31837", format: .code128),
        .init(id: "bidfood", name: "Bidfood", domain: "bidfood.nl", category: "Supermarkt", colorHex: "#E30613", format: .code128),
        .init(id: "kiko", name: "KIKO Milano", domain: "kikocosmetics.com", category: "Drogist en beauty", colorHex: "#1A1A1A", format: .ean13, aliases: ["kiko"]),
        .init(id: "lush", name: "Lush", domain: "lush.com", category: "Drogist en beauty", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "sephora", name: "Sephora", domain: "sephora.nl", category: "Drogist en beauty", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "loccitane", name: "L'Occitane", domain: "loccitane.com", category: "Drogist en beauty", colorHex: "#F5B700", format: .ean13, aliases: ["l'occitane", "loccitane"]),
        .init(id: "mooi", name: "MOOI parfumerie", domain: "mooi.nl", category: "Drogist en beauty", colorHex: "#1A1A1A", format: .ean13, aliases: ["mooi"]),
        .init(id: "pourvous", name: "Pour Vous", domain: "pourvous.nl", category: "Drogist en beauty", colorHex: "#E6007E", format: .ean13),
        .init(id: "kapper", name: "Kapper (eigen kaart)", domain: "", category: "Drogist en beauty", colorHex: "#8E8E93", format: .code128, aliases: ["kapsalon"]),
        .init(id: "blushy", name: "Blushy", domain: "blushy.nl", category: "Drogist en beauty", colorHex: "#E6007E", format: .ean13),
        .init(id: "lookfantastic", name: "Lookfantastic", domain: "lookfantastic.nl", category: "Drogist en beauty", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "apotheekbenu", name: "Apotheek (BENU of eigen)", domain: "benu.nl", category: "Optiek en zorg", colorHex: "#E30613", format: .code128, aliases: ["apotheek"]),
        .init(id: "mediq", name: "Mediq Apotheek", domain: "mediq.nl", category: "Optiek en zorg", colorHex: "#003B7E", format: .code128, aliases: ["mediq"]),
        .init(id: "hudson", name: "Hudson's Bay", domain: "hudsonsbay.nl", category: "Warenhuis en wonen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "hema2", name: "HEMA Kids", domain: "hema.nl", category: "Warenhuis en wonen", colorHex: "#E30613", format: .ean13),
        .init(id: "flyingtiger", name: "Flying Tiger Copenhagen", domain: "flyingtiger.com", category: "Warenhuis en wonen", colorHex: "#1A1A1A", format: .ean13, aliases: ["flying tiger"]),
        .init(id: "casa", name: "Casa", domain: "casashops.com", category: "Warenhuis en wonen", colorHex: "#E30613", format: .ean13),
        .init(id: "dille", name: "Dille & Kamille", domain: "dille-kamille.nl", category: "Warenhuis en wonen", colorHex: "#2E5E3E", format: .ean13, aliases: ["dille en kamille"]),
        .init(id: "hollandhome", name: "Home&Garden (Intratuin)", domain: "intratuin.nl", category: "Warenhuis en wonen", colorHex: "#78B829", format: .ean13),
        .init(id: "goossens", name: "Goossens", domain: "goossens.nl", category: "Warenhuis en wonen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "leenbakker2", name: "Leen Bakker Voordeelpas", domain: "leenbakker.nl", category: "Warenhuis en wonen", colorHex: "#E30613", format: .ean13),
        .init(id: "trendhopper", name: "Trendhopper", domain: "trendhopper.nl", category: "Warenhuis en wonen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "beddenreus", name: "Beddenreus", domain: "beddenreus.nl", category: "Warenhuis en wonen", colorHex: "#E30613", format: .ean13),
        .init(id: "swiss", name: "Swiss Sense", domain: "swisssense.nl", category: "Warenhuis en wonen", colorHex: "#E30613", format: .ean13),
        .init(id: "montel", name: "Montel", domain: "montel.nl", category: "Warenhuis en wonen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "blokkerb", name: "Blokker cadeaukaart", domain: "blokker.nl", category: "Cadeaukaarten", colorHex: "#E3001B", format: .code128, kind: .voucher),
        .init(id: "kruidvatv", name: "Kruidvat cadeaukaart", domain: "kruidvat.nl", category: "Cadeaukaarten", colorHex: "#E2001A", format: .code128, kind: .voucher),
        .init(id: "action2", name: "Action cadeaukaart", domain: "action.com", category: "Cadeaukaarten", colorHex: "#0071CE", format: .code128, kind: .voucher),
        .init(id: "primark", name: "Primark", domain: "primark.com", category: "Mode en schoenen", colorHex: "#00A3E0", format: .ean13),
        .init(id: "zara", name: "Zara", domain: "zara.com", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "mango", name: "Mango", domain: "mango.com", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "jackjones", name: "JACK & JONES", domain: "jackjones.com", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13, aliases: ["jack jones"]),
        .init(id: "vero", name: "VERO MODA", domain: "veromoda.com", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13, aliases: ["vero moda"]),
        .init(id: "costes", name: "Costes", domain: "costesfashion.com", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "msmode", name: "MS Mode", domain: "msmode.nl", category: "Mode en schoenen", colorHex: "#E6007E", format: .ean13),
        .init(id: "didi", name: "DIDI", domain: "didi.nl", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "sting", name: "The Sting", domain: "thesting.com", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13, aliases: ["sting"]),
        .init(id: "cool", name: "CoolCat", domain: "coolcat.nl", category: "Mode en schoenen", colorHex: "#E30613", format: .ean13, aliases: ["cool cat"]),
        .init(id: "america", name: "America Today", domain: "americatoday.com", category: "Mode en schoenen", colorHex: "#003B7E", format: .ean13),
        .init(id: "score", name: "Score", domain: "score.nl", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "bijenkorfgift", name: "de Bijenkorf cadeaukaart", domain: "debijenkorf.nl", category: "Cadeaukaarten", colorHex: "#1A1A1A", format: .code128, kind: .voucher),
        .init(id: "hm2", name: "H&M cadeaukaart", domain: "hm.com", category: "Cadeaukaarten", colorHex: "#E50010", format: .code128, kind: .voucher),
        .init(id: "omoda", name: "Omoda", domain: "omoda.nl", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "vanhaaren2", name: "Schoenenreus", domain: "schoenenreus.nl", category: "Mode en schoenen", colorHex: "#E30613", format: .ean13),
        .init(id: "dungelmann", name: "Dungelmann", domain: "dungelmann.nl", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "zalando", name: "Zalando Plus", domain: "zalando.nl", category: "Mode en schoenen", colorHex: "#FF6900", format: .qr, aliases: ["zalando"]),
        .init(id: "wehkamp", name: "Wehkamp", domain: "wehkamp.nl", category: "Mode en schoenen", colorHex: "#E6007E", format: .code128),
        .init(id: "hunkemoller2", name: "Hunkemöller cadeaukaart", domain: "hunkemoller.nl", category: "Cadeaukaarten", colorHex: "#1A1A1A", format: .code128, kind: .voucher),
        .init(id: "sissyboy", name: "Sissy-Boy", domain: "sissy-boy.com", category: "Mode en schoenen", colorHex: "#1A1A1A", format: .ean13, aliases: ["sissy boy"]),
        .init(id: "wefashion2", name: "Miss Etam cadeaukaart", domain: "missetam.nl", category: "Cadeaukaarten", colorHex: "#C8102E", format: .code128, kind: .voucher),
        .init(id: "zeeman2", name: "Zeeman cadeaukaart", domain: "zeeman.com", category: "Cadeaukaarten", colorHex: "#0060A9", format: .code128, kind: .voucher),
        .init(id: "bristol2", name: "Van Haren cadeaukaart", domain: "vanharen.nl", category: "Cadeaukaarten", colorHex: "#E30613", format: .code128, kind: .voucher),
        .init(id: "formido", name: "Formido", domain: "formido.nl", category: "Klussen, tuin en dieren", colorHex: "#E30613", format: .ean13),
        .init(id: "hornbach2", name: "HORNBACH cadeaukaart", domain: "hornbach.nl", category: "Cadeaukaarten", colorHex: "#F7941D", format: .code128, kind: .voucher),
        .init(id: "ranzijn", name: "Ranzijn", domain: "ranzijn.nl", category: "Klussen, tuin en dieren", colorHex: "#00843D", format: .ean13),
        .init(id: "tuinland", name: "Tuinland", domain: "tuinland.nl", category: "Klussen, tuin en dieren", colorHex: "#78B829", format: .ean13),
        .init(id: "overvecht", name: "Tuincentrum Overvecht", domain: "tuincentrumovervecht.nl", category: "Klussen, tuin en dieren", colorHex: "#78B829", format: .ean13),
        .init(id: "discus", name: "Discus", domain: "discus.nl", category: "Klussen, tuin en dieren", colorHex: "#E30613", format: .ean13),
        .init(id: "brico", name: "Brico", domain: "brico.nl", category: "Klussen, tuin en dieren", colorHex: "#E30613", format: .ean13),
        .init(id: "hubo2", name: "Bouwmaat", domain: "bouwmaat.nl", category: "Klussen, tuin en dieren", colorHex: "#E30613", format: .code128),
        .init(id: "hornbachpro", name: "Hornbach Profi", domain: "hornbach.nl", category: "Klussen, tuin en dieren", colorHex: "#F7941D", format: .code128),
        .init(id: "petsplace2", name: "Dierspeciaalzaak (eigen kaart)", domain: "", category: "Klussen, tuin en dieren", colorHex: "#8E8E93", format: .code128, aliases: ["dierenwinkel"]),
        .init(id: "zooplus", name: "zooplus", domain: "zooplus.nl", category: "Klussen, tuin en dieren", colorHex: "#00843D", format: .code128),
        .init(id: "fietsenwinkel", name: "Fietsenwinkel.nl", domain: "fietsenwinkel.nl", category: "Klussen, tuin en dieren", colorHex: "#E30613", format: .ean13),
        .init(id: "halfords", name: "Halfords", domain: "halfords.nl", category: "Klussen, tuin en dieren", colorHex: "#F28C00", format: .ean13),
        .init(id: "profile", name: "Profile Tyrecenter", domain: "profile.nl", category: "Klussen, tuin en dieren", colorHex: "#E30613", format: .code128),
        .init(id: "coolblue", name: "Coolblue", domain: "coolblue.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#0090E3", format: .code128),
        .init(id: "bcc", name: "BCC", domain: "bcc.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E30613", format: .ean13),
        .init(id: "ep", name: "EP:", domain: "ep.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E30613", format: .ean13, aliases: ["ep"]),
        .init(id: "gamemania", name: "Game Mania", domain: "gamemania.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E30613", format: .ean13),
        .init(id: "bartsmit", name: "Bart Smit", domain: "bartsmit.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E30613", format: .ean13),
        .init(id: "lego", name: "LEGO Insiders", domain: "lego.com", category: "Elektronica, boeken en speelgoed", colorHex: "#E3000B", format: .qr, aliases: ["lego"]),
        .init(id: "fun", name: "Fun Speelgoed", domain: "fun.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E6007E", format: .ean13, aliases: ["fun"]),
        .init(id: "broekhuis", name: "Broekhuis", domain: "broekhuis.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "boekhandel", name: "Boekhandel (Libris/Blz.)", domain: "libris.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#1A1A1A", format: .ean13, aliases: ["blz"]),
        .init(id: "waterstones", name: "Waterstones", domain: "waterstones.com", category: "Elektronica, boeken en speelgoed", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "donner", name: "Donner", domain: "donner.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#1A1A1A", format: .ean13),
        .init(id: "amazon", name: "Amazon", domain: "amazon.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#FF9900", format: .qr),
        .init(id: "bol2", name: "bol (lid)", domain: "bol.com", category: "Elektronica, boeken en speelgoed", colorHex: "#0000A4", format: .code128, aliases: ["bol select"]),
        .init(id: "hobbyshop", name: "Hobbyshop (eigen kaart)", domain: "", category: "Elektronica, boeken en speelgoed", colorHex: "#8E8E93", format: .code128),
        .init(id: "hobbydos", name: "Hobbydos", domain: "hobbydos.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E30613", format: .ean13),
        .init(id: "pipoos", name: "Pipoos", domain: "pipoos.nl", category: "Elektronica, boeken en speelgoed", colorHex: "#E6007E", format: .ean13),
        .init(id: "decathlon2", name: "Decathlon cadeaukaart", domain: "decathlon.nl", category: "Cadeaukaarten", colorHex: "#0082C3", format: .code128, kind: .voucher),
        .init(id: "trainmore", name: "TrainMore", domain: "trainmore.nl", category: "Sport en fitness", colorHex: "#E30613", format: .qr),
        .init(id: "fitforfree", name: "Fit For Free", domain: "fitforfree.nl", category: "Sport en fitness", colorHex: "#E30613", format: .qr),
        .init(id: "snapfitness", name: "Snap Fitness", domain: "snapfitness.com", category: "Sport en fitness", colorHex: "#6A1B9A", format: .qr),
        .init(id: "bigsfitness", name: "Big Gym", domain: "biggym.nl", category: "Sport en fitness", colorHex: "#1A1A1A", format: .qr),
        .init(id: "fit20", name: "fit20", domain: "fit20.nl", category: "Sport en fitness", colorHex: "#E30613", format: .qr),
        .init(id: "health-city", name: "HealthCity", domain: "healthcity.nl", category: "Sport en fitness", colorHex: "#E30613", format: .qr, aliases: ["health city"]),
        .init(id: "zwembad", name: "Zwembad (eigen kaart)", domain: "", category: "Sport en fitness", colorHex: "#0A84FF", format: .code128, aliases: ["zwembad"]),
        .init(id: "golf", name: "Golfbaan (eigen kaart)", domain: "", category: "Sport en fitness", colorHex: "#34C759", format: .code128),
        .init(id: "runnersworld", name: "Runnersworld", domain: "runnersworld.nl", category: "Sport en fitness", colorHex: "#E30613", format: .ean13),
        .init(id: "aktiesport", name: "Aktiesport", domain: "aktiesport.nl", category: "Sport en fitness", colorHex: "#F28C00", format: .ean13),
        .init(id: "sportdirect", name: "Sports Direct", domain: "sportsdirect.com", category: "Sport en fitness", colorHex: "#1A1A1A", format: .ean13, aliases: ["sportsdirect"]),
        .init(id: "asadventure", name: "A.S.Adventure", domain: "asadventure.nl", category: "Sport en fitness", colorHex: "#2E5E3E", format: .ean13, aliases: ["as adventure"]),
        .init(id: "bfit", name: "Sportschool (eigen pas)", domain: "", category: "Sport en fitness", colorHex: "#8E8E93", format: .qr, aliases: ["sportschool"]),
        .init(id: "gulf", name: "Gulf", domain: "gulf.nl", category: "Tanken en sparen", colorHex: "#F68B1F", format: .code128),
        .init(id: "argos", name: "Argos", domain: "argos-oil.com", category: "Tanken en sparen", colorHex: "#E30613", format: .code128),
        .init(id: "avia", name: "AVIA", domain: "avia.nl", category: "Tanken en sparen", colorHex: "#E30613", format: .code128),
        .init(id: "firezone", name: "Firezone", domain: "firezone.nl", category: "Tanken en sparen", colorHex: "#E30613", format: .code128),
        .init(id: "q8", name: "Q8", domain: "q8.nl", category: "Tanken en sparen", colorHex: "#003B7E", format: .code128),
        .init(id: "fastned", name: "Fastned", domain: "fastnedcharging.com", category: "Tanken en sparen", colorHex: "#FFD500", format: .qr),
        .init(id: "travelcard", name: "Travelcard", domain: "travelcard.nl", category: "Tanken en sparen", colorHex: "#003B7E", format: .code128),
        .init(id: "multitankcard", name: "MultiTankcard", domain: "multitankcard.nl", category: "Tanken en sparen", colorHex: "#E30613", format: .code128),
        .init(id: "flyingblue", name: "Flying Blue", domain: "flyingblue.com", category: "Tanken en sparen", colorHex: "#00205B", format: .code128, aliases: ["klm"]),
        .init(id: "payback", name: "Payback", domain: "payback.de", category: "Tanken en sparen", colorHex: "#00338D", format: .code128),
        .init(id: "ns", name: "NS Flex", domain: "ns.nl", category: "Tanken en sparen", colorHex: "#FFC917", format: .qr, aliases: ["ns"]),
        .init(id: "ovpas", name: "OV-pas (eigen)", domain: "ov-chipkaart.nl", category: "Tanken en sparen", colorHex: "#00A0E2", format: .code128, aliases: ["ov-chipkaart"]),
        .init(id: "qpark", name: "Q-Park", domain: "q-park.nl", category: "Tanken en sparen", colorHex: "#0072CE", format: .qr),
        .init(id: "yellowbrick", name: "Yellowbrick", domain: "yellowbrick.nl", category: "Tanken en sparen", colorHex: "#FFD500", format: .code128),
        .init(id: "greenwheels", name: "Greenwheels", domain: "greenwheels.nl", category: "Tanken en sparen", colorHex: "#00843D", format: .code128),
        .init(id: "anwbcamping", name: "ACSI CampingCard", domain: "acsi.eu", category: "Tanken en sparen", colorHex: "#00843D", format: .code128, aliases: ["acsi"]),
        .init(id: "schiphol", name: "Schiphol Parking", domain: "schiphol.nl", category: "Tanken en sparen", colorHex: "#141251", format: .qr),
        .init(id: "cineville", name: "Cineville", domain: "cineville.nl", category: "Uitgaan en vrije tijd", colorHex: "#1A1A1A", format: .qr),
        .init(id: "filmhuis", name: "Filmhuis (eigen kaart)", domain: "", category: "Uitgaan en vrije tijd", colorHex: "#8E8E93", format: .code128),
        .init(id: "euroscoop", name: "Euroscoop", domain: "euroscoop.nl", category: "Uitgaan en vrije tijd", colorHex: "#E30613", format: .qr),
        .init(id: "kinepolis2", name: "Kinepolis Unlimited", domain: "kinepolis.nl", category: "Uitgaan en vrije tijd", colorHex: "#1D1D1B", format: .qr),
        .init(id: "efteling", name: "Efteling abonnement", domain: "efteling.com", category: "Uitgaan en vrije tijd", colorHex: "#7A0026", format: .qr, aliases: ["efteling"]),
        .init(id: "walibi", name: "Walibi Holland", domain: "walibi.nl", category: "Uitgaan en vrije tijd", colorHex: "#E6007E", format: .qr, aliases: ["walibi"]),
        .init(id: "artis", name: "ARTIS", domain: "artis.nl", category: "Uitgaan en vrije tijd", colorHex: "#1A1A1A", format: .qr),
        .init(id: "blijdorp", name: "Diergaarde Blijdorp", domain: "diergaardeblijdorp.nl", category: "Uitgaan en vrije tijd", colorHex: "#00843D", format: .qr, aliases: ["blijdorp"]),
        .init(id: "burgerszoo", name: "Burgers' Zoo", domain: "burgerszoo.nl", category: "Uitgaan en vrije tijd", colorHex: "#2E5E3E", format: .qr, aliases: ["burgers zoo"]),
        .init(id: "dierenpark", name: "Dierentuin (abonnement)", domain: "", category: "Uitgaan en vrije tijd", colorHex: "#34C759", format: .qr, aliases: ["dierentuin"]),
        .init(id: "natuurmonumenten", name: "Natuurmonumenten", domain: "natuurmonumenten.nl", category: "Uitgaan en vrije tijd", colorHex: "#00843D", format: .code128),
        .init(id: "staatsbosbeheer", name: "Staatsbosbeheer", domain: "staatsbosbeheer.nl", category: "Uitgaan en vrije tijd", colorHex: "#00843D", format: .code128),
        .init(id: "rijksmuseum", name: "Rijksmuseum vriend", domain: "rijksmuseum.nl", category: "Uitgaan en vrije tijd", colorHex: "#1A1A1A", format: .qr),
        .init(id: "theater", name: "Theaterkaart (eigen)", domain: "", category: "Uitgaan en vrije tijd", colorHex: "#AF52DE", format: .code128, aliases: ["theater"]),
        .init(id: "ticketmaster", name: "Ticketmaster", domain: "ticketmaster.nl", category: "Uitgaan en vrije tijd", colorHex: "#026CDF", format: .qr),
        .init(id: "stadspas", name: "Stadspas", domain: "", category: "Uitgaan en vrije tijd", colorHex: "#E30613", format: .code128, aliases: ["stadspas", "ooievaarspas", "rotterdampas"]),
        .init(id: "rotterdampas", name: "Rotterdampas", domain: "rotterdampas.nl", category: "Uitgaan en vrije tijd", colorHex: "#00843D", format: .code128),
        .init(id: "ooievaarspas", name: "Ooievaarspas", domain: "denhaag.nl", category: "Uitgaan en vrije tijd", colorHex: "#E30613", format: .code128),
        .init(id: "studentenkaart", name: "Studentenpas (eigen)", domain: "", category: "Uitgaan en vrije tijd", colorHex: "#5E5CE6", format: .code128, aliases: ["studentenkaart"]),
        .init(id: "bieb2", name: "Bibliotheekpas (eigen bieb)", domain: "", category: "Uitgaan en vrije tijd", colorHex: "#E6007E", format: .code39),
        .init(id: "bowling", name: "Bowlingcentrum (eigen kaart)", domain: "", category: "Uitgaan en vrije tijd", colorHex: "#8E8E93", format: .code128),
        .init(id: "center", name: "Center Parcs", domain: "centerparcs.nl", category: "Uitgaan en vrije tijd", colorHex: "#00843D", format: .qr),
        .init(id: "landal", name: "Landal GreenParks", domain: "landal.nl", category: "Uitgaan en vrije tijd", colorHex: "#5A8C2B", format: .qr, aliases: ["landal"]),
        .init(id: "roompot", name: "Roompot", domain: "roompot.nl", category: "Uitgaan en vrije tijd", colorHex: "#003B7E", format: .qr),
        .init(id: "mcdonalds", name: "McDonald's", domain: "mcdonalds.nl", category: "Drank en eten", colorHex: "#FFC72C", format: .qr, aliases: ["mcdonalds"]),
        .init(id: "burgerking", name: "Burger King", domain: "burgerking.nl", category: "Drank en eten", colorHex: "#D62300", format: .qr),
        .init(id: "kfc", name: "KFC", domain: "kfc.nl", category: "Drank en eten", colorHex: "#E4002B", format: .qr),
        .init(id: "dominos", name: "Domino's", domain: "dominos.nl", category: "Drank en eten", colorHex: "#006491", format: .qr, aliases: ["dominos"]),
        .init(id: "newyorkpizza", name: "New York Pizza", domain: "newyorkpizza.nl", category: "Drank en eten", colorHex: "#00843D", format: .qr),
        .init(id: "subway", name: "Subway", domain: "subway.com", category: "Drank en eten", colorHex: "#008C15", format: .qr),
        .init(id: "febo", name: "FEBO", domain: "febo.nl", category: "Drank en eten", colorHex: "#E30613", format: .qr),
        .init(id: "bakkerbart", name: "Bakker Bart", domain: "bakkerbart.nl", category: "Drank en eten", colorHex: "#E30613", format: .qr),
        .init(id: "lebon", name: "Le Pain Quotidien", domain: "lepainquotidien.com", category: "Drank en eten", colorHex: "#3B3A36", format: .qr),
        .init(id: "bagels", name: "Bagels & Beans", domain: "bagelsbeans.nl", category: "Drank en eten", colorHex: "#E30613", format: .qr, aliases: ["bagels and beans"]),
        .init(id: "coffeecompany", name: "Coffee Company", domain: "coffeecompany.nl", category: "Drank en eten", colorHex: "#1A1A1A", format: .qr),
        .init(id: "kiosk", name: "Kiosk (NS)", domain: "ns.nl", category: "Drank en eten", colorHex: "#FFC917", format: .qr),
        .init(id: "lpq", name: "La Place", domain: "laplace.com", category: "Drank en eten", colorHex: "#E30613", format: .qr),
        .init(id: "vanderValk", name: "Van der Valk", domain: "valk.com", category: "Drank en eten", colorHex: "#00843D", format: .code128, aliases: ["toekan"]),
        .init(id: "fletcher", name: "Fletcher Hotels", domain: "fletcher.nl", category: "Drank en eten", colorHex: "#003B7E", format: .code128),
        .init(id: "hotelgift", name: "Hotel cadeaukaart", domain: "", category: "Cadeaukaarten", colorHex: "#8E8E93", format: .code128, kind: .voucher),
        .init(id: "dinercadeau", name: "Diner Cadeau", domain: "dinercadeau.nl", category: "Cadeaukaarten", colorHex: "#7F1734", format: .code128, kind: .voucher),
        .init(id: "wijncadeau", name: "Wijn Cadeau", domain: "wijncadeau.nl", category: "Cadeaukaarten", colorHex: "#7F1734", format: .code128, kind: .voucher),
        .init(id: "ytickets", name: "YourGift", domain: "yourgift.nl", category: "Cadeaukaarten", colorHex: "#E6007E", format: .code128, aliases: ["yourgift"], kind: .voucher),
        .init(id: "toppers", name: "Toppers cadeaukaart", domain: "", category: "Cadeaukaarten", colorHex: "#8E8E93", format: .code128, kind: .voucher),
        .init(id: "podiumcadeau", name: "Podium Cadeaukaart", domain: "podiumcadeaukaart.nl", category: "Cadeaukaarten", colorHex: "#AF52DE", format: .code128, aliases: ["podium"], kind: .voucher),
        .init(id: "museumcadeau", name: "Museum Cadeaukaart", domain: "museumcadeaukaart.nl", category: "Cadeaukaarten", colorHex: "#E30613", format: .code128, kind: .voucher),
        .init(id: "fashioncheque", name: "Fashioncheque", domain: "fashioncheque.com", category: "Cadeaukaarten", colorHex: "#1A1A1A", format: .code128, kind: .voucher),
        .init(id: "intratuincadeau", name: "Tuinbon", domain: "tuinbon.nl", category: "Cadeaukaarten", colorHex: "#78B829", format: .code128, aliases: ["tuinbon"], kind: .voucher),
        .init(id: "sportcadeau", name: "Sport Cadeaukaart", domain: "", category: "Cadeaukaarten", colorHex: "#0082C3", format: .code128, kind: .voucher),
        .init(id: "beautycadeau", name: "Beauty Cadeaukaart", domain: "", category: "Cadeaukaarten", colorHex: "#E6007E", format: .code128, kind: .voucher),
        .init(id: "appstore", name: "App Store en iTunes-kaart", domain: "apple.com", category: "Cadeaukaarten", colorHex: "#1A1A1A", format: .code128, aliases: ["itunes"], kind: .voucher),
        .init(id: "googleplay", name: "Google Play-kaart", domain: "play.google.com", category: "Cadeaukaarten", colorHex: "#34A853", format: .code128, kind: .voucher),
        .init(id: "netflixgift", name: "Netflix-cadeaukaart", domain: "netflix.com", category: "Cadeaukaarten", colorHex: "#E50914", format: .code128, kind: .voucher),
        .init(id: "spotifygift", name: "Spotify-cadeaukaart", domain: "spotify.com", category: "Cadeaukaarten", colorHex: "#1DB954", format: .code128, kind: .voucher),
        .init(id: "playstation", name: "PlayStation Store-kaart", domain: "playstation.com", category: "Cadeaukaarten", colorHex: "#003791", format: .code128, kind: .voucher),
        .init(id: "xbox", name: "Xbox-cadeaukaart", domain: "xbox.com", category: "Cadeaukaarten", colorHex: "#107C10", format: .code128, kind: .voucher),
        .init(id: "nintendo", name: "Nintendo eShop-kaart", domain: "nintendo.com", category: "Cadeaukaarten", colorHex: "#E60012", format: .code128, kind: .voucher),
        .init(id: "steam", name: "Steam-cadeaukaart", domain: "steampowered.com", category: "Cadeaukaarten", colorHex: "#1B2838", format: .code128, kind: .voucher),
        .init(id: "zalandogift", name: "Zalando cadeaukaart", domain: "zalando.nl", category: "Cadeaukaarten", colorHex: "#FF6900", format: .code128, kind: .voucher),
        .init(id: "ikea3", name: "IKEA Family (zakelijk)", domain: "ikea.com", category: "Warenhuis en wonen", colorHex: "#0058A3", format: .code128, aliases: ["ikea business"]),
        .init(id: "eyewish", name: "Eyewish", domain: "eyewish.nl", category: "Optiek en zorg", colorHex: "#E6007E", format: .ean13),
        .init(id: "schoonenberg", name: "Schoonenberg", domain: "schoonenberg.nl", category: "Optiek en zorg", colorHex: "#003B7E", format: .ean13),
        .init(id: "beterhoren", name: "Beter Horen", domain: "beterhoren.nl", category: "Optiek en zorg", colorHex: "#E30613", format: .ean13),
        .init(id: "bloedbank", name: "Sanquin donorpas", domain: "sanquin.nl", category: "Optiek en zorg", colorHex: "#E30613", format: .code128, aliases: ["sanquin"]),
        .init(id: "zorgverzekeraar", name: "Zorgpas (eigen verzekeraar)", domain: "", category: "Optiek en zorg", colorHex: "#0A84FF", format: .code128, aliases: ["zorgpas"]),
        .init(id: "tandarts", name: "Tandarts (eigen kaart)", domain: "", category: "Optiek en zorg", colorHex: "#8E8E93", format: .code128),
        .init(id: "dierenarts", name: "Dierenarts (eigen kaart)", domain: "", category: "Optiek en zorg", colorHex: "#8E8E93", format: .code128),
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
        StoreTemplates.normalizedDomain(website) ?? StoreTemplates.normalizedDomain(StoreTemplates.template(id: templateID)?.domain)
    }
}
