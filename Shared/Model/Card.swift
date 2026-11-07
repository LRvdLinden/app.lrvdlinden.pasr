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
