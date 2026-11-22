import Foundation

/// Stempelkaart (sinds 1.0.3): een aantal vakjes, een stempel per aankoop, en bij een volle kaart de beloning.
/// Alleen een zakelijke kaart (Pasr voor ondernemers): de zaak zet de stempels, de app toont alleen de stand.
/// Eigen stempelkaarten (build 42) worden bij het opstarten eenmalig een klantenkaart (OwnStampMigration).
extension CardDetails {
    static let stampsRange = 2...30
    static let defaultStamps = 10

    /// Vakjes, altijd binnen 2...30.
    var stampsTotalValue: Int { min(max(stampsTotal ?? Self.defaultStamps, Self.stampsRange.lowerBound), Self.stampsRange.upperBound) }
    /// Stempels, altijd binnen 0...vakjes.
    var stampsCountValue: Int { min(max(stampsCount ?? 0, 0), stampsTotalValue) }
    var stampsLeft: Int { stampsTotalValue - stampsCountValue }
    var stampsFull: Bool { stampsCountValue >= stampsTotalValue }
    var isBusiness: Bool { issuer == "business" && businessCardId != nil }

    /// "nog 3 tot je beloning" of "Vol: wissel je beloning in".
    var stampsProgressText: String {
        if stampsFull { return String(localized: "Vol: wissel je beloning in") }
        let rewardText = reward?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        if stampsLeft == 1 {
            return rewardText.map { String(localized: "nog 1 tot \($0)") } ?? String(localized: "nog 1 tot je beloning")
        }
        return rewardText.map { String(localized: "nog \(stampsLeft) tot \($0)") } ?? String(localized: "nog \(stampsLeft) tot je beloning")
    }

    /// Voor Wallet en meldingen: "●●●●●●●○○○".
    var stampsDots: String {
        String(repeating: "\u{25CF}", count: stampsCountValue) + String(repeating: "\u{25CB}", count: stampsLeft)
    }
}

extension Card {
    /// Een eigen stempelkaart uit build 42 (geen zakelijke kaart). Die bestaat na de migratie niet meer.
    var isOwnStampCard: Bool { kind == .stamps && !details.isBusiness }

    /// De notitie die een eigen stempelkaart bij de migratie krijgt: "Stempelkaart: 4 van 10, beloning: 1 gratis koffie".
    static func ownStampNote(_ d: CardDetails) -> String {
        let reward = d.reward?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let stand = String(localized: "Stempelkaart: \(d.stampsCountValue) van \(d.stampsTotalValue)")
        return reward.map { stand + String(localized: ", beloning: \($0)") } ?? stand
    }

    /// Eigen stempelkaart -> klantenkaart met de stand in de notitie. Geeft true als er iets veranderde.
    /// Idempotent: staat de notitie er al (bijv. via iCloud van een ander apparaat), dan komt hij er niet nog eens bij.
    @discardableResult
    func convertOwnStampCard() -> Bool {
        guard isOwnStampCard else { return false }
        let line = Self.ownStampNote(details)
        if !note.contains(line) {
            note = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? line : note + "\n" + line
        }
        kind = .loyalty
        var d = details
        d.stampsTotal = nil
        d.stampsCount = nil
        d.reward = nil
        details = d
        updatedAt = .now
        return true
    }
}

/// Eenmalig bij het opstarten (en elke keer als de app naar voren komt, voor kaarten die later via iCloud, een back-up
/// of een gedeelde link binnenkomen): eigen stempelkaarten worden klantenkaarten. De klant kan nergens meer zelf
/// stempels zetten; dat doet alleen de zaak (Pasr Zakelijk of pasr.nl/zakelijk/scan).
enum OwnStampMigration {
    @MainActor
    static func run(_ cards: [Card]) -> Int {
        var n = 0
        for card in cards where card.deletedAt == nil && card.isOwnStampCard {
            if card.convertOwnStampCard() { n += 1 }
        }
        return n
    }
}
