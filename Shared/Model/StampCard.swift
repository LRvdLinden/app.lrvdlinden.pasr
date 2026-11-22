import Foundation

/// Stempelkaart (sinds 1.0.3): een aantal vakjes, een stempel per aankoop, en bij een volle kaart de beloning.
/// Eigen kaarten zet je zelf af (een tik); een zakelijke kaart (Pasr voor ondernemers) volgt de stand van de zaak.
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
    /// Een stempelkaart die je zelf bijhoudt (geen zakelijke kaart, niet tijdelijk gedeeld).
    var stampsEditable: Bool { kind == .stamps && !details.isBusiness && !isTemporary }

    /// Stempel erbij (+1) of eraf (-1). Geeft true als de kaart nu vol is geworden.
    @discardableResult
    func changeStamps(by delta: Int) -> Bool {
        var d = details
        let wasFull = d.stampsFull
        d.stampsTotal = d.stampsTotalValue
        d.stampsCount = min(max(d.stampsCountValue + delta, 0), d.stampsTotalValue)
        details = d
        updatedAt = .now
        return !wasFull && d.stampsFull
    }

    /// Beloning ingewisseld: de kaart begint weer leeg.
    func redeemStamps() {
        var d = details
        d.stampsTotal = d.stampsTotalValue
        d.stampsCount = 0
        details = d
        updatedAt = .now
    }
}
