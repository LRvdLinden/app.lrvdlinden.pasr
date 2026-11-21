import Foundation

/// Gegevens die alleen bij sommige soorten passen horen. Klein en als JSON bewaard (Card.detailsData), zodat het
/// datamodel en de synchronisatie niet voor elke soort een eigen veld nodig hebben. Alles is optioneel.
struct CardDetails: Codable, Equatable, Hashable {
    // Ticket
    var eventDate: Date?
    var venue: String?
    var seat: String?
    // Abonnement
    var renewsAt: Date?
    var cost: Double?
    /// "week", "month", "quarter" of "year" (zie CardDetails.Period).
    var period: String?
    // Kortingscode: true = de code als barcode/QR tonen; nil of false = als tekst.
    var codeAsBarcode: Bool?
    /// Onderschriften bij foto 1 tot en met 4.
    var captions: [String]?

    var isEmpty: Bool { self == CardDetails() }

    enum Period: String, CaseIterable, Identifiable {
        case week, month, quarter, year
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week: String(localized: "per week")
            case .month: String(localized: "per maand")
            case .quarter: String(localized: "per kwartaal")
            case .year: String(localized: "per jaar")
            }
        }
        var name: String {
            switch self {
            case .week: String(localized: "Week")
            case .month: String(localized: "Maand")
            case .quarter: String(localized: "Kwartaal")
            case .year: String(localized: "Jaar")
            }
        }
    }

    var periodValue: Period { period.flatMap(Period.init(rawValue:)) ?? .month }

    /// Voor de synchronisatie via het account (datums als ISO 8601).
    var json: [String: Any] {
        var d: [String: Any] = [:]
        let f = ISO8601DateFormatter()
        d["eventDate"] = eventDate.map { f.string(from: $0) }
        d["venue"] = venue
        d["seat"] = seat
        d["renewsAt"] = renewsAt.map { f.string(from: $0) }
        d["cost"] = cost
        d["period"] = period
        d["codeAsBarcode"] = codeAsBarcode
        d["captions"] = captions
        return d
    }

    init() {}

    init(json d: [String: Any]) {
        let f = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ key: String) -> Date? {
            (d[key] as? String).flatMap { f.date(from: $0) ?? fractional.date(from: $0) }
        }
        eventDate = date("eventDate")
        venue = d["venue"] as? String
        seat = d["seat"] as? String
        renewsAt = date("renewsAt")
        cost = (d["cost"] as? NSNumber)?.doubleValue
        period = d["period"] as? String
        codeAsBarcode = d["codeAsBarcode"] as? Bool
        captions = (d["captions"] as? [String]).map { Array($0.prefix(Card.maxNotePhotos)) }
    }
}

extension Card {
    static let maxNotePhotos = 4

    var details: CardDetails {
        get { detailsData.flatMap { try? JSONDecoder().decode(CardDetails.self, from: $0) } ?? CardDetails() }
        set { detailsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    /// Kortingscode die als tekst wordt getoond (de standaard), niet als barcode.
    var showsCodeAsText: Bool { kind == .code && details.codeAsBarcode != true }

    /// De foto-notities op volgorde (lege plekken overgeslagen).
    var notePhotos: [Data] { [photo1, photo2, photo3, photo4].compactMap { $0 } }

    func setNotePhotos(_ photos: [Data]) {
        let list = Array(photos.prefix(Self.maxNotePhotos))
        photo1 = list.count > 0 ? list[0] : nil
        photo2 = list.count > 1 ? list[1] : nil
        photo3 = list.count > 2 ? list[2] : nil
        photo4 = list.count > 3 ? list[3] : nil
    }
}

/// Cadeaubon-gids van een winkel, uit het beheer (pasr_stores.guide, via de catalogus). Alles optioneel: wat onbekend
/// is, staat er niet in.
struct StoreGuide: Codable, Hashable {
    var validity: String?
    var online: Bool?
    var store: Bool?
    var how: String?
    var shipping: String?
    var termsURL: String?
    var checked: String?

    enum CodingKeys: String, CodingKey {
        case validity, online, store, how, shipping, checked
        case termsURL = "terms_url"
    }

    var isEmpty: Bool {
        validity == nil && online == nil && store == nil && how == nil && shipping == nil && terms == nil
    }

    /// Alleen https-adressen.
    var terms: URL? {
        guard let termsURL, let url = URL(string: termsURL), url.scheme == "https" else { return nil }
        return url
    }

    /// Uit een rij van de catalogus (JSONSerialization).
    init?(json: Any?) {
        guard let dict = json as? [String: Any] else { return nil }
        validity = (dict["validity"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        online = dict["online"] as? Bool
        store = dict["store"] as? Bool
        how = (dict["how"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        shipping = (dict["shipping"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        termsURL = dict["terms_url"] as? String
        checked = dict["checked"] as? String
        if isEmpty { return nil }
    }

    /// Datum van controle, als "12 nov 2026".
    var checkedText: String? {
        guard let checked else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: checked)?.formatted(date: .abbreviated, time: .omitted)
    }
}
