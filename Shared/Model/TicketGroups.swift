import Foundation

// MARK: Tickets groeperen (zoals Apple Wallet)
//
// Tickets voor hetzelfde evenement op dezelfde dag staan in de stapel als één item ("3 tickets"). Open je het, dan
// veeg je horizontaal van ticket naar ticket, elk met een eigen code.
//
// Sleutel: genormaliseerde eventnaam + dag van CardDetails.eventDate (lokale kalender). De eventnaam is de naam van
// het ticket tot het eerste streepje: "Drakenboot – Regular", "Drakenboot – KIDS Early Bird" en een zelf toegevoegd
// "Drakenboot" horen dus bij elkaar. Niets nieuws in de opslag of de synchronisatie: eventDate bestaat al sinds 1.0.2.
// Android doet precies hetzelfde (data/TicketGroups.kt).

extension Card {
    /// Scheidingstekens tussen evenement en tickettype ("Drakenboot – Early Bird").
    private static let ticketTypeSeparators = [" – ", " — ", " - ", " | ", ": "]

    /// "Drakenboot – KIDS Early Bird" → "Drakenboot".
    static func ticketEventTitle(_ name: String) -> String {
        var title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in ticketTypeSeparators {
            if let range = title.range(of: separator) {
                let head = title[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                if !head.isEmpty { title = head }
            }
        }
        return title
    }

    /// Kleine letters, zonder accenten en leestekens: "Drakenboot 2027!" → "drakenboot2027".
    static func normalizedEventKey(_ name: String) -> String {
        ticketEventTitle(name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "nl_NL"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    /// Groepeersleutel van een ticket met datum; nil voor andere kaarten (die staan altijd los).
    /// Tijdelijk gedeelde tickets blijven los: die hebben hun eigen einde en regels.
    var ticketGroupKey: String? {
        guard kind == .ticket, deletedAt == nil, !isTemporary, let date = details.eventDate else { return nil }
        let event = Card.normalizedEventKey(storeName)
        guard !event.isEmpty else { return nil }
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(event)|\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
    }
}

/// Eén item in de stapel: een losse kaart, of een groep tickets voor hetzelfde evenement op dezelfde dag.
struct CardStackItem: Identifiable {
    /// Nooit leeg; bij een groep A tot Z op naam (bijv. Early Bird, KIDS Early Bird, Regular).
    let cards: [Card]

    /// Het id van de eerste kaart: blijft gelijk zolang de groep bestaat.
    var id: UUID { cards[0].id }
    var first: Card { cards[0] }
    var isGroup: Bool { cards.count > 1 }
    func contains(_ id: UUID) -> Bool { cards.contains { $0.id == id } }

    /// Naam van het evenement voor de groep ("Drakenboot"); bij een losse kaart gewoon de naam.
    var title: String { isGroup ? Card.ticketEventTitle(first.storeName) : first.storeName }

    /// "3 tickets".
    var countText: String { String(localized: "\(cards.count) tickets") }
}

extension Array where Element == Card {
    /// Groepeert tickets voor hetzelfde evenement op dezelfde dag; de volgorde van de lijst blijft (een groep staat waar
    /// zijn eerste ticket stond). Al het andere blijft een los item.
    func stackItems() -> [CardStackItem] {
        var order: [String] = []
        var buckets: [String: [Card]] = [:]
        for card in self {
            let key = card.ticketGroupKey ?? "card:\(card.id.uuidString)"
            if buckets[key] == nil { order.append(key); buckets[key] = [] }
            buckets[key]?.append(card)
        }
        return order.compactMap { key in
            guard let list = buckets[key], !list.isEmpty else { return nil }
            return CardStackItem(cards: list.count > 1 ? list.alphabetical() : list)
        }
    }
}
