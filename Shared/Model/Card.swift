import Foundation
import SwiftData

/// A loyalty card or voucher. Every property has a default or is optional so that
/// SwiftData can mirror it to the user's private CloudKit database.
@Model
final class Card {
    var id: UUID = UUID()
    var kindRaw: String = CardKind.loyalty.rawValue
    var storeName: String = ""
    var templateID: String?
    /// Encrypted end to end in iCloud: only your own devices hold the key.
    @Attribute(.allowsCloudEncryption) var number: String = ""
    var formatRaw: String = BarcodeFormat.code128.rawValue
    var colorHex: String = "#2B2F3A"
    @Attribute(.allowsCloudEncryption) var note: String = ""
    var isFavorite: Bool = false
    var useCount: Int = 0
    var lastUsed: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Voucher
    var balance: Double?
    var currencyCode: String?
    @Attribute(.allowsCloudEncryption) var pin: String?
    var expiresAt: Date?

    /// Set when the card is moved to Recently Deleted; purged after 30 days.
    var deletedAt: Date?

    /// The store's website, used to fetch its logo (e.g. "ah.nl"). Falls back to the template's.
    var website: String?
    /// True when `logoData` was fetched from the store's website rather than chosen by the user.
    var logoFromWebsite: Bool = false
    /// The code stays hidden until Face ID confirms it's you (handy for vouchers with a balance).
    var isLocked: Bool = false
    /// Gedeelde Pasr waarin deze kaart staat; nil = privé. Een kaart verhuizen maakt een kopie met een nieuw id.
    var groupID: UUID?

    // Tijdelijk met mij gedeeld (zie TempShare): tot wanneer, de code op de server en of de deler eerder stopte.
    var sharedUntil: Date?
    var shareToken: String?
    var shareRevoked: Bool = false

    /// Eigen locaties (JSON van [CardPlace], hoogstens 10): "Ik sta hier" of een speld op de kaart. Gaan voor bij
    /// "Kaart tonen bij de winkel" en op de Wallet-pas.
    var placesData: Data?

    /// Geschiedenis (JSON van [CardEvent]): wanneer je de kaart liet zien, en bij een voucher wat je uitgaf of
    /// opwaardeerde. Hoogstens 90 dagen en 150 regels.
    var historyData: Data?
    /// Saldo-pagina van de uitgever (voucher); anders die van de winkel uit de catalogus.
    var balanceURL: String?

    @Attribute(.externalStorage) var logoData: Data?
    @Attribute(.externalStorage) var frontPhoto: Data?
    @Attribute(.externalStorage) var backPhoto: Data?
    /// A pre-rendered PNG of a 2D code, so the Watch (which has no Core Image) can show it.
    @Attribute(.externalStorage) var codeImage: Data?

    init(storeName: String = "", number: String = "", format: BarcodeFormat = .code128,
         kind: CardKind = .loyalty, colorHex: String = "#2B2F3A") {
        self.storeName = storeName
        self.number = number
        self.formatRaw = format.rawValue
        self.kindRaw = kind.rawValue
        self.colorHex = colorHex
    }

    var kind: CardKind {
        get { CardKind(rawValue: kindRaw) ?? .loyalty }
        set { kindRaw = newValue.rawValue }
    }

    var format: BarcodeFormat {
        get { BarcodeFormat(rawValue: formatRaw) ?? .code128 }
        set { formatRaw = newValue.rawValue }
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Calendar.current.startOfDay(for: .now)
    }

    /// Een tijdelijk met mij gedeelde kaart: niet naar Wallet, niet verder delen, niet naar Watch of widgets.
    var isTemporary: Bool { shareToken != nil }

    /// Tijdelijke kaart voorbij het einde (of gestopt door de deler): de code wordt nergens meer getoond.
    var isShareExpired: Bool { isTemporary && (shareRevoked || (sharedUntil ?? .distantPast) <= .now) }

    func markUsed() {
        useCount += 1
        lastUsed = .now
    }
}

extension Array where Element == Card {
    /// Always A to Z by store name, everywhere (wallet, Watch, widgets).
    func alphabetical() -> [Card] {
        sorted { a, b in
            let order = a.storeName.localizedStandardCompare(b.storeName)
            if order != .orderedSame { return order == .orderedAscending }
            return a.number < b.number
        }
    }
}

extension Card {
    /// Usage count, weighted down as the last use gets older (half-life of 30 days).
    static func score(_ card: Card) -> Double {
        guard let lastUsed = card.lastUsed else { return 0 }
        let days = max(0, Date.now.timeIntervalSince(lastUsed) / 86_400)
        return Double(card.useCount) * pow(0.5, days / 30)
    }
}


/// Een eigen locatie van een kaart: een filiaal dat je zelf hebt vastgezet.
struct CardPlace: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double

    static let maxPerCard = 10
}

extension Card {
    var places: [CardPlace] {
        get { placesData.flatMap { try? JSONDecoder().decode([CardPlace].self, from: $0) } ?? [] }
        set { placesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(Array(newValue.prefix(CardPlace.maxPerCard))) }
    }
}


/// Een regel in de geschiedenis van een kaart.
struct CardEvent: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case shown, spent, topup, set }
    var id = UUID()
    var date = Date()
    var kind: Kind
    /// Bedrag van de uitgave of opwaardering (positief).
    var amount: Double?
    /// Tegoed na deze regel (voucher).
    var balance: Double?
    /// Waar (filiaal, als dat bekend was).
    var place: String?

    static let keepDays: Double = 90
    static let maxCount = 150
}

extension Card {
    var history: [CardEvent] {
        get { historyData.flatMap { try? JSONDecoder().decode([CardEvent].self, from: $0) } ?? [] }
        set {
            let cutoff = Date.now.addingTimeInterval(-CardEvent.keepDays * 86_400)
            let kept = newValue.filter { $0.date > cutoff }.sorted { $0.date > $1.date }.prefix(CardEvent.maxCount)
            historyData = kept.isEmpty ? nil : try? JSONEncoder().encode(Array(kept))
        }
    }

    /// Laatst getoond (uit de geschiedenis, anders lastUsed).
    var lastShown: CardEvent? { history.first { $0.kind == .shown } }

    /// Kaart getoond. Binnen 10 minuten nog eens dezelfde kaart telt niet opnieuw (wel de plek als die er nog niet was).
    func recordShown(place: String?) {
        var list = history
        if let last = list.first(where: { $0.kind == .shown }), Date.now.timeIntervalSince(last.date) < 600 {
            if last.place == nil, let place, let i = list.firstIndex(of: last) { list[i].place = place; history = list }
            return
        }
        list.insert(CardEvent(kind: .shown, place: place), at: 0)
        history = list
    }

    /// Uitgegeven (voucher): tegoed omlaag, nooit onder nul.
    func recordSpent(_ amount: Double, place: String?) {
        let new = max(0, (balance ?? 0) - amount)
        balance = (new * 100).rounded() / 100
        var list = history
        list.insert(CardEvent(kind: .spent, amount: amount, balance: balance, place: place), at: 0)
        history = list
        updatedAt = .now
    }

    /// Opgewaardeerd of tegoed gecorrigeerd (bijvoorbeeld na Saldo checken).
    func recordTopUp(_ amount: Double) {
        balance = (((balance ?? 0) + amount) * 100).rounded() / 100
        var list = history
        list.insert(CardEvent(kind: .topup, amount: amount, balance: balance), at: 0)
        history = list
        updatedAt = .now
    }

    func recordBalance(_ value: Double) {
        balance = (max(0, value) * 100).rounded() / 100
        var list = history
        list.insert(CardEvent(kind: .set, balance: balance), at: 0)
        history = list
        updatedAt = .now
    }

    /// Een regel weghalen; bij een uitgave of opwaardering gaat het tegoed terug.
    func removeEvent(_ event: CardEvent) {
        switch event.kind {
        case .spent: if let a = event.amount { balance = (balance ?? 0) + a }
        case .topup: if let a = event.amount { balance = max(0, (balance ?? 0) - a) }
        default: break
        }
        if let b = balance { balance = (b * 100).rounded() / 100 }
        history = history.filter { $0.id != event.id }
        updatedAt = .now
    }
}
