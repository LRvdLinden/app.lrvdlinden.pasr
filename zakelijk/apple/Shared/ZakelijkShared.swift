import Foundation

// Gedeeld tussen de apps (iOS en Mac) en de widgets (iOS en Mac): app group, links naar een scherm in de app en de
// cache met cijfers die de app bijwerkt en de widgets lezen. Geen netwerk en geen sessie in de widgets: alleen deze cache.

/// App group van Pasr Zakelijk (iOS en macOS, zelfde id; aanzetten bij de App ID's in het developer portal).
enum ZakelijkAppGroup {
    static let id = "group.app.lrvdlinden.pasrzakelijk"

    /// Map van de app group, of nil zonder ondertekening/app group (dan geen widgetgegevens).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}

/// Onderdelen van de app, met dezelfde ids als het dashboard op pasr.nl/zakelijk/dashboard.
enum ZakelijkSection: String, CaseIterable, Codable, Hashable, Identifiable {
    case vandaag
    case scannen
    case stempelkaarten
    case klantenkaarten
    case tickets
    case kortingsbonnen
    case actiecodes
    case gezamenlijkeActies = "gezamenlijke-acties"
    case beloningen
    case inzichten
    case marketing
    case promotiemateriaal
    case vestigingen
    case medewerkers
    case instellingen

    var id: String { rawValue }
}

/// Link naar een scherm: `pasrzakelijk://open/<onderdeel>?zaak=<id>&id=<item>` (widgets, meldingen met `app_url`).
enum ZakelijkLink {
    static let scheme = "pasrzakelijk"

    static func url(_ section: ZakelijkSection, business: String? = nil, item: String? = nil) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "open"
        c.path = "/" + section.rawValue
        var items: [URLQueryItem] = []
        if let business, !business.isEmpty { items.append(URLQueryItem(name: "zaak", value: business)) }
        if let item, !item.isEmpty { items.append(URLQueryItem(name: "id", value: item)) }
        c.queryItems = items.isEmpty ? nil : items
        return c.url ?? URL(string: "\(scheme)://open/vandaag")!
    }

    struct Target: Equatable {
        var section: ZakelijkSection
        var business: String?
        var item: String?
    }

    static func parse(_ url: URL) -> Target? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == "open" else { return nil }
        let name = url.pathComponents.filter { $0 != "/" }.first?.lowercased() ?? ZakelijkSection.vandaag.rawValue
        let section = ZakelijkSection(rawValue: name) ?? .vandaag
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? {
            guard let v = items.first(where: { $0.name == key })?.value?.trimmingCharacters(in: .whitespaces),
                  !v.isEmpty, v.count <= 80 else { return nil }
            return v
        }
        return Target(section: section, business: value("zaak"), item: value("id"))
    }
}

/// Wat de widgets laten zien, per zaak. De app schrijft dit na elk verversen; de widgets lezen het.
struct WidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    var businesses: [Business]

    struct Business: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var isOwner: Bool
        var today: Today
        var event: Event?
        var todo: [TodoItem]
    }

    /// Cijfers van vandaag en de stempels van de laatste 7 dagen (oudste eerst, vandaag laatst).
    struct Today: Codable, Equatable {
        var stamps: Int
        var rewards: Int
        var joins: Int
        var trend: [Int]
        /// Stempels op dezelfde dag vorige week (voor de pijl omhoog/omlaag).
        var lastWeekStamps: Int?
    }

    struct Event: Codable, Equatable {
        var id: String
        var name: String
        var startsAt: Date
        var endsAt: Date
        var registered: Int
        var checkedIn: Int
        var capacity: Int
    }

    struct TodoItem: Codable, Equatable, Identifiable {
        enum Kind: String, Codable { case invite, draft, expiring }
        var id: String
        var kind: Kind
        /// Al vertaald door de app (taal van de app).
        var title: String
        var detail: String
        var date: Date?
        var section: ZakelijkSection
        var item: String?
    }

    func business(_ id: String?) -> Business? {
        guard let id, !id.isEmpty else { return businesses.first }
        return businesses.first { $0.id == id } ?? businesses.first
    }

    static let placeholder = WidgetSnapshot(updatedAt: .now, businesses: [
        Business(id: "voorbeeld", name: "Koffiebar Anna", isOwner: true,
                 today: Today(stamps: 42, rewards: 5, joins: 7, trend: [18, 25, 31, 22, 37, 29, 42], lastWeekStamps: 33),
                 event: Event(id: "e", name: "Proeverij", startsAt: .now.addingTimeInterval(2 * 86_400),
                              endsAt: .now.addingTimeInterval(2 * 86_400 + 7_200), registered: 64, checkedIn: 0, capacity: 80),
                 todo: [])
    ])
}

/// Bestand in de app group met de laatste WidgetSnapshot.
enum WidgetStore {
    static let kind = "app.lrvdlinden.pasrzakelijk.widgets"

    private static var fileURL: URL? {
        ZakelijkAppGroup.containerURL?.appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Bewaart de snapshot; true als er iets veranderde (dan de widgets verversen).
    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL else { return false }
        if let old = load(), old.businesses == snapshot.businesses,
           snapshot.updatedAt.timeIntervalSince(old.updatedAt) < 15 * 60 { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        return (try? data.write(to: url, options: [.atomic])) != nil
    }

    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
