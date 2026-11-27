import Foundation

/// Evenementgegevens van een ticket-sjabloon uit het beheer (pasr_stores.guide, via de catalogus; zie TicketEvent in
/// supabase/functions/admin/stores.ts). Alles optioneel: wat onbekend is, staat er niet in.
struct TicketEvent: Codable, Hashable {
    var event: String?
    var brand: String?
    /// Eerste en (bij meerdaagse evenementen) laatste dag, "YYYY-MM-DD".
    var date: String?
    var endDate: String?
    /// Toegang van/tot, "HH:MM".
    var doors: String?
    var ends: String?
    var venue: String?
    var city: String?
    var address: String?
    var ticketType: String?
    var ticketNote: String?
    var infoURL: String?
    var textHex: String?
    var labelHex: String?

    /// Uit de gids van een rij van de catalogus (JSONSerialization); nil als er geen evenementgegevens in staan.
    init?(json: Any?) {
        guard let d = json as? [String: Any] else { return nil }
        func s(_ key: String, _ max: Int = 120) -> String? {
            (d[key] as? String).map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max)) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        event = s("event", 60); brand = s("brand", 30); date = s("date", 10); endDate = s("end_date", 10)
        doors = s("doors", 5); ends = s("ends", 5); venue = s("venue", 60); city = s("city", 40); address = s("address")
        ticketType = s("ticket_type", 30); ticketNote = s("ticket_note", 40); infoURL = s("info_url", 300)
        textHex = s("text_hex", 7); labelHex = s("label_hex", 7)
        if self == TicketEvent.empty { return nil }
    }

    private init() {}
    private static let empty = TicketEvent()

    static func day(_ text: String?) -> Date? {
        guard let text else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text + " 12:00")
    }
}

/// Wat een ticket laat zien, opgezocht uit het sjabloon in de catalogus (merk, titel, soort, datum, tijden, locatie)
/// en aangevuld met wat de gebruiker bij de kaart invulde (datum, locatie, plaats). Gebruikt door TicketFaceView
/// (iOS, Watch, widgets) en de Wallet-pas.
struct TicketInfo: Equatable, Hashable {
    /// Naam naast het logo (meestal in hoofdletters getoond), bijv. "Drakenboot".
    var brand: String
    /// Titel, bijv. "Drakenboot 2027".
    var title: String
    /// Soort ticket, bijv. "Early Bird", en een korte toelichting, bijv. "t/m 14 jaar".
    var type: String?
    var note: String?
    var dateText: String?
    var timeText: String?
    var venue: String?
    var city: String?
    var address: String?
    var seat: String?
    var info: URL?
    var textHex: String?
    var labelHex: String?
    /// Zelfde sleutel = zelfde evenement (voor groeperen, ook de groupingIdentifier van de Wallet-pas).
    var groupKey: String
    /// Eerste dag (met begintijd als die bekend is), voor sorteren en de Wallet-pas.
    var start: Date?
    /// Rauwe velden voor de Wallet-pas.
    var event: TicketEvent?
    /// Ticket van een zaak (Pasr Zakelijk): naam van de houder, status en de plek op de kaart.
    var holder: String?
    var status: String?
    var doorsText: String?
    var isBusiness = false
    /// Headerafbeelding van het event (https), achter de kop van het hoge ticket.
    var header: URL?
    var latitude: Double?
    var longitude: Double?

    /// "Zwitsalpark, Apeldoorn"
    var place: String? {
        let parts = [venue, city].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Kaarten-app met de route naar het evenement (adres, anders locatie en plaats).
    var routeURL: URL? {
        if let latitude, let longitude {
            var c = URLComponents(string: "https://maps.apple.com/")
            c?.queryItems = [URLQueryItem(name: "daddr", value: "\(latitude),\(longitude)")]
            if let a = address { c?.queryItems?.append(URLQueryItem(name: "q", value: a)) }
            return c?.url
        }
        guard let target = (address?.isEmpty == false ? address : place) else { return nil }
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "daddr", value: target)]
        return c?.url
    }

    /// Titel en soort uit een naam als "Drakenboot – Early Bird".
    static func split(_ name: String) -> (title: String, type: String?) {
        for sep in [" – ", " - ", " — "] {
            if let r = name.range(of: sep) {
                let type = name[r.upperBound...].trimmingCharacters(in: .whitespaces)
                return (name[..<r.lowerBound].trimmingCharacters(in: .whitespaces), type.isEmpty ? nil : type)
            }
        }
        return (name.trimmingCharacters(in: .whitespaces), nil)
    }

    static func groupKey(for text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "nl_NL")).lowercased()
        let slug = folded.map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return "pasr-event-" + (slug.isEmpty ? "ticket" : slug)
    }

    /// Ticket van een zaak (pasr_my_event_tickets): alles komt van de server, niets uit de catalogus.
    static func business(name: String, details d: CardDetails) -> TicketInfo {
        var info = TicketInfo(brand: d.businessName ?? name, title: name, type: d.ticketTypeName,
                              groupKey: "pasr-event-" + (d.eventId ?? d.ticketId ?? "ticket"))
        info.holder = d.holderName
        info.status = d.ticketStatus
        info.address = d.address
        info.latitude = d.latitude
        info.longitude = d.longitude
        info.start = d.eventDate
        if let start = d.eventDate {
            info.dateText = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
            var time = start.formatted(date: .omitted, time: .shortened)
            if let end = d.eventEnd, end > start {
                time += " – " + (Calendar.current.isDate(end, inSameDayAs: start)
                                 ? end.formatted(date: .omitted, time: .shortened)
                                 : end.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
            }
            info.timeText = time
        }
        info.doorsText = d.doorsAt?.formatted(date: .omitted, time: .shortened)
        info.venue = d.address
        info.isBusiness = true
        info.header = d.headerURL.flatMap(URL.init(string:))
        return info
    }

    /// Het ticket van een kaart: sjabloon uit de catalogus (op id) plus de eigen gegevens van de kaart.
    static func resolve(name: String, templateID: String?, details: CardDetails, website: String? = nil,
                        event given: TicketEvent? = nil) -> TicketInfo {
        if details.isEventTicket { return business(name: name, details: details) }
        let event = given ?? RemoteStores.event(for: templateID)
        let parts = split(name.isEmpty ? String(localized: "Ticket") : name)
        let title = event?.event ?? parts.title
        let brand = event?.brand ?? split(event?.event ?? parts.title).title
        var info = TicketInfo(brand: brand, title: title, type: event?.ticketType ?? parts.type, note: event?.ticketNote,
                              groupKey: groupKey(for: event?.event ?? parts.title))
        info.event = event
        info.venue = (details.venue?.isEmpty == false ? details.venue : nil) ?? event?.venue
        info.city = details.venue?.isEmpty == false ? nil : event?.city
        info.address = event?.address
        info.seat = details.seat?.isEmpty == false ? details.seat : nil
        info.textHex = event?.textHex
        info.labelHex = event?.labelHex
        if let raw = event?.infoURL, let url = URL(string: raw), url.scheme == "https" {
            info.info = url
        } else if let site = website?.trimmingCharacters(in: .whitespaces), !site.isEmpty,
                  let url = URL(string: site.hasPrefix("http") ? site : "https://" + site), url.scheme == "https" {
            info.info = url
        }
        let dayStyle = Date.FormatStyle.dateTime.day().month(.wide).year()
        if let own = details.eventDate {
            // eigen datum bij de kaart gaat voor
            info.dateText = own.formatted(dayStyle)
            let comps = Calendar.current.dateComponents([.hour, .minute], from: own)
            if comps.hour != 0 || comps.minute != 0 { info.timeText = own.formatted(date: .omitted, time: .shortened) }
            info.start = own
        } else if let first = TicketEvent.day(event?.date) {
            if let last = TicketEvent.day(event?.endDate), last > first {
                let sameMonth = Calendar.current.isDate(first, equalTo: last, toGranularity: .month)
                let from = sameMonth ? first.formatted(.dateTime.day()) : first.formatted(.dateTime.day().month(.wide))
                info.dateText = from + " – " + last.formatted(dayStyle)
            } else {
                info.dateText = first.formatted(dayStyle)
            }
            info.start = first
        }
        if info.timeText == nil, let doors = event?.doors {
            info.timeText = event?.ends.map { "\(doors) – \($0)" } ?? String(localized: "vanaf \(doors)")
        }
        return info
    }
}

extension RemoteStores {
    /// Evenementgegevens van een ticket-sjabloon uit het beheer.
    static func event(for templateID: String?) -> TicketEvent? {
        guard let id = templateID?.lowercased(), !id.isEmpty else { return nil }
        return load().first { $0.id.lowercased() == id }?.event
    }
}

extension Card {
    /// Het ticket zoals Pasr het toont (alleen zinvol bij een kaart van soort ticket).
    var ticketInfo: TicketInfo {
        TicketInfo.resolve(name: storeName, templateID: templateID, details: details, website: website)
    }
}
