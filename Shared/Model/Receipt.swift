import Foundation
import SwiftData

/// Een bewaard kassabonnetje (sinds build 47), los of bij een gebruiksmoment van een kaart. Voor garantie: met een
/// optionele datum "Garantie tot" en een herinnering een maand van tevoren.
///
/// Opslag zoals de foto's van een pas: in SwiftData met de beelden als externe bestanden, op het toestel onder iOS
/// Gegevensbescherming (versleuteld), in je eigen iCloud (privédatabase) en in de versleutelde back-up van Pasr. De bon
/// gaat niet via het Pasr-account naar de server. Alle velden optioneel of met een standaardwaarde (eis van CloudKit).
@Model
final class Receipt {
    var id: UUID = UUID()
    /// De kaart waar de bon bij hoort (Card.id); nil als de kaart weg is.
    var cardID: UUID?
    /// Het gebruiksmoment (CardEvent.id) waar de bon bij hoort, als die er is.
    var useID: UUID?
    /// Winkelnaam zoals de bon is bewaard (blijft staan als de kaart wordt verwijderd).
    var storeName: String = ""
    /// Datum op de bon (voorgevuld uit de tekstherkenning, door jou gecontroleerd).
    var date: Date = Date()
    /// Totaalbedrag op de bon.
    var total: Double?
    var currencyCode: String?
    /// Wat je kocht (optioneel, bijvoorbeeld "Wasmachine"), om op te zoeken.
    @Attribute(.allowsCloudEncryption) var title: String = ""
    @Attribute(.allowsCloudEncryption) var note: String = ""
    /// Garantie tot (optioneel); Pasr herinnert je een maand van tevoren.
    var warrantyUntil: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// De gescande pagina's (JPEG, hoogstens 2000 pixels), zoals de foto's van een pas.
    @Attribute(.externalStorage) var page1: Data?
    @Attribute(.externalStorage) var page2: Data?
    @Attribute(.externalStorage) var page3: Data?
    @Attribute(.externalStorage) var page4: Data?

    init(cardID: UUID? = nil, useID: UUID? = nil, storeName: String = "", date: Date = .now) {
        self.cardID = cardID
        self.useID = useID
        self.storeName = storeName
        self.date = date
    }

    static let maxPages = 4

    var pages: [Data] {
        get { [page1, page2, page3, page4].compactMap { $0 } }
        set {
            let list = Array(newValue.prefix(Self.maxPages))
            page1 = list.count > 0 ? list[0] : nil
            page2 = list.count > 1 ? list[1] : nil
            page3 = list.count > 2 ? list[2] : nil
            page4 = list.count > 3 ? list[3] : nil
        }
    }

    /// Garantie loopt nog (vandaag of later).
    var warrantyActive: Bool {
        guard let warrantyUntil else { return false }
        return warrantyUntil >= Calendar.current.startOfDay(for: .now)
    }

    /// Standaard voorstel: 2 jaar vanaf de datum op de bon (wettelijke garantie in de praktijk vaak langer).
    static func defaultWarranty(from date: Date) -> Date {
        Calendar.current.date(byAdding: .year, value: 2, to: date) ?? date
    }

    /// Tekst waarop je kunt zoeken: winkel, wat je kocht, notitie, bedrag ("12,50" en "12.50") en datum.
    var searchText: String {
        let nl = Locale(identifier: "nl_NL")
        var parts = [storeName, title, note]
        if let total {
            parts.append(total.formatted(.number.precision(.fractionLength(2)).locale(nl)))
            parts.append(String(format: "%.2f", total))
        }
        parts.append(date.formatted(.dateTime.day().month(.wide).year().locale(nl)))
        parts.append(date.formatted(.dateTime.day().month(.twoDigits).year().locale(nl)))
        return parts.joined(separator: " ")
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let hay = searchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return q.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(separator: " ").allSatisfy { hay.contains($0) }
    }
}
