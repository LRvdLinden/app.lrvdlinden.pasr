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
    // Stempelkaart (sinds 1.0.3)
    /// Aantal vakjes (2 tot 30).
    var stampsTotal: Int?
    /// Gezette stempels (0 tot en met stampsTotal).
    var stampsCount: Int?
    /// De beloning, bijv. "1 gratis koffie".
    var reward: String?
    /// "business" als de kaart van een ondernemer komt (Pasr voor ondernemers); de stand komt dan van de server.
    var issuer: String?
    /// Kaart van de zaak (pasr_business_cards.id) en de code die de zaak scant (pasr_business_members.member_code).
    var businessCardId: String?
    var memberCode: String?
    // Gratis ticket van een zaak (Pasr Zakelijk, pasr_my_event_tickets; issuer "event"). De server is de bron:
    // Pasr zet deze velden bij elke verversing opnieuw. Geboortedatum en e-mail staan hier nooit in.
    var eventId: String?
    var ticketId: String?
    /// "registered", "checked_in"/"used", "waitlist" of "cancelled".
    var ticketStatus: String?
    var holderName: String?
    var ticketTypeName: String?
    var eventEnd: Date?
    var doorsAt: Date?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var headerURL: String?
    var businessName: String?
    /// Waar het logo vandaan kwam (adres van de server), zodat Pasr het pas opnieuw ophaalt als het verandert.
    var logoSource: String?
    // Klantenkaart met barcode van een zaak (pasr_my_member_cards; issuer "member").
    var memberId: String?
    var memberCardId: String?
    var discountNow: MemberDiscount?
    var nextDiscount: MemberDiscount?
    var savingCount: Int?
    var savingTarget: Int?
    var savingReward: String?
    var savingCanRedeem: Bool?
    /// Melding bij een nieuwe kortingsperiode (pasr_member_card_notify).
    var memberNotify: Bool?

    var isEmpty: Bool { self == CardDetails() }

    /// Ticket voor een event van een zaak (van de server, niet zelf toegevoegd).
    var isEventTicket: Bool { issuer == "event" && ticketId != nil }
    /// Klantenkaart met barcode van een zaak.
    var isMemberCard: Bool { issuer == "member" && memberId != nil }
    /// Komt van de server (ticket of klantenkaart van een zaak): niet via de kaartsynchronisatie, niet zelf wijzigen.
    var isServerItem: Bool { isEventTicket || isMemberCard }

    var ticketCancelled: Bool { ticketStatus == "cancelled" }
    var ticketUsed: Bool { ticketStatus == "checked_in" || ticketStatus == "used" }
    var ticketWaitlist: Bool { ticketStatus == "waitlist" }

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
        d["stampsTotal"] = stampsTotal
        d["stampsCount"] = stampsCount
        d["reward"] = reward
        d["issuer"] = issuer
        d["businessCardId"] = businessCardId
        d["memberCode"] = memberCode
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
        stampsTotal = (d["stampsTotal"] as? NSNumber)?.intValue
        stampsCount = (d["stampsCount"] as? NSNumber)?.intValue
        reward = d["reward"] as? String
        issuer = d["issuer"] as? String
        businessCardId = d["businessCardId"] as? String
        memberCode = d["memberCode"] as? String
    }
}

/// Korting op een klantenkaart van een zaak: nu (`until` = t/m) of de volgende (`startsAt`).
struct MemberDiscount: Codable, Equatable, Hashable {
    var percent: Double?
    var label: String?
    var until: Date?
    var startsAt: Date?

    /// Uit de server-JSON ({percent, label, until} of {percent, label, starts_at}); nil als er niets bruikbaars in staat.
    init?(json: Any?) {
        guard let d = json as? [String: Any] else { return nil }
        percent = (d["percent"] as? NSNumber)?.doubleValue ?? (d["percent"] as? String).flatMap(Double.init)
        label = (d["label"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : String($0.prefix(80)) }
        until = MemberDiscount.date(d["until"] ?? d["ends_on"] ?? d["ends_at"])
        startsAt = MemberDiscount.date(d["starts_at"] ?? d["starts_on"])
        if percent == nil && label == nil { return nil }
    }

    /// "15%" (zonder ",0").
    var percentText: String? {
        guard let percent else { return nil }
        return percent.rounded() == percent ? "\(Int(percent))%" : String(format: "%.1f%%", percent)
    }

    /// Server-datum: ISO 8601 / Postgres ("2026-12-19T16:00:00Z", "2026-12-19 16:00:00.123+00") of alleen "YYYY-MM-DD"
    /// (dan 12:00 Nederlandse tijd, zodat de dag in elke tijdzone klopt).
    static func date(_ value: Any?) -> Date? {
        guard var s = (value as? String)?.trimmingCharacters(in: .whitespaces), s.count >= 10 else { return nil }
        if s.count == 10 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "Europe/Amsterdam")
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return f.date(from: s + " 12:00")
        }
        s = s.replacingOccurrences(of: " ", with: "T")
        // fractie weg
        if let dot = s.firstIndex(of: ".") {
            let rest = s[s.index(after: dot)...]
            let tz = rest.firstIndex { !$0.isNumber } ?? rest.endIndex
            s = String(s[..<dot]) + String(rest[tz...])
        }
        // "+00" → "+00:00"
        if let r = s.range(of: "[+-][0-9]{2}$", options: .regularExpression) { s.replaceSubrange(r, with: s[r] + ":00") }
        if s.count == 19 { s += "Z" }
        return ISO8601DateFormatter().date(from: s)
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
    // Klantenkaart (programmagids): zo spaar je, voordelen, officiële programmapagina.
    var earn: String?
    var perks: [String]?
    var programURL: String?
    /// Verjaardagsvoordeel (sinds 1.0.3), bijv. "Gratis taartje in je verjaardagsmaand".
    var birthday: String?

    enum CodingKeys: String, CodingKey {
        case validity, online, store, how, shipping, checked, earn, perks, birthday
        case termsURL = "terms_url"
        case programURL = "program_url"
    }

    var isEmpty: Bool {
        validity == nil && online == nil && store == nil && how == nil && shipping == nil && terms == nil
            && earn == nil && (perks ?? []).isEmpty && program == nil && birthday == nil
    }

    /// Heeft iets voor een cadeaukaart (geldigheid, waar, uitleg, verzendkosten, voorwaarden).
    var hasGiftInfo: Bool {
        validity != nil || online != nil || store != nil || how != nil || shipping != nil || terms != nil
    }

    /// Heeft iets voor een klantenkaart (sparen, voordelen, programmapagina).
    var hasProgramInfo: Bool { earn != nil || !(perks ?? []).isEmpty || program != nil || birthday != nil }

    var program: URL? {
        guard let programURL, let url = URL(string: programURL), url.scheme == "https" else { return nil }
        return url
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
        earn = (dict["earn"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // voordelen: een lijst, of één tekst (met regels of puntkomma's)
        if let list = dict["perks"] as? [String] {
            perks = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else if let text = dict["perks"] as? String {
            perks = text.split(whereSeparator: { $0 == "\n" || $0 == ";" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if perks?.isEmpty == true { perks = nil }
        programURL = dict["program_url"] as? String
        birthday = (dict["birthday"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : String($0.prefix(160)) }
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

extension String {
    /// nil voor een lege tekst.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
