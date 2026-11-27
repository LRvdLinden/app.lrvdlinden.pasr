import Foundation

// Tickets (gratis events) en klantenkaarten met barcode. Databasefuncties volgens het gedeelde contract
// (pasr_business_event_*, pasr_business_ticket_scan, pasr_business_member_card_*). Alles tolerant gelezen:
// ontbreekt een veld, dan een nette standaardwaarde.

extension JSONObject {
    func double(_ keys: String...) -> Double? {
        for k in keys {
            if let v = raw[k] as? NSNumber { return v.doubleValue }
            if let v = raw[k] as? String, let d = Double(v.replacingOccurrences(of: ",", with: ".")) { return d }
        }
        return nil
    }

    func ints(_ key: String) -> [Int]? {
        guard let list = raw[key] as? [Any] else { return nil }
        return list.compactMap { ($0 as? NSNumber)?.intValue ?? ($0 as? String).flatMap { Int($0) } }
    }
}

/// Vaste notaties voor de server: datum, tijd en tijdstip met tijdzone.
enum TKFormat {
    private static let zone = TimeZone(identifier: "Europe/Amsterdam") ?? .current
    private static func make(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = pattern
        return f
    }
    private static let dayF = make("yyyy-MM-dd")
    private static let timeF = make("HH:mm")
    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func day(_ d: Date) -> String { dayF.string(from: d) }
    static func time(_ d: Date) -> String { timeF.string(from: d) }
    static func timestamp(_ d: Date) -> String { stamp.string(from: d) }
    static func parseDay(_ s: String?) -> Date? { s.flatMap { dayF.date(from: String($0.prefix(10))) } }
    /// "17:00" of "17:00:00" → datum van vandaag met die tijd (alleen uur en minuut tellen).
    static func parseTime(_ s: String?) -> Date? { s.flatMap { timeF.date(from: String($0.prefix(5))) } }

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    /// "za 19 dec · 16:00–19:00"
    static func eventLine(_ start: Date, _ end: Date?) -> String {
        var s = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " · " + start.formatted(date: .omitted, time: .shortened)
        if let end { s += "–" + end.formatted(date: .omitted, time: .shortened) }
        return s
    }

    /// "di 17:00" binnen een week, anders "17 dec 17:00".
    static func soon(_ d: Date) -> String {
        if d.timeIntervalSinceNow < 6 * 86_400 {
            return d.formatted(.dateTime.weekday(.abbreviated)) + " " + d.formatted(date: .omitted, time: .shortened)
        }
        return d.formatted(.dateTime.day().month(.abbreviated)) + " " + d.formatted(date: .omitted, time: .shortened)
    }

    static func percent(_ p: Double) -> String {
        p.rounded() == p ? String(Int(p)) : String(format: "%.1f", p)
    }
}

// MARK: Tickets

struct TicketType: Identifiable, Hashable {
    /// Alleen voor de lijst in beeld; het id van de server staat in serverID.
    var id = UUID().uuidString
    var serverID: String
    var name: String
    var capacity: Int?

    init(serverID: String = "", name: String = "", capacity: Int? = nil) {
        self.serverID = serverID; self.name = name; self.capacity = capacity
    }

    init(json j: JSONObject) {
        self.init(serverID: j.string("id") ?? "", name: j.string("name") ?? "", capacity: j.int("capacity"))
    }

    var payload: [String: Any] {
        var p: [String: Any] = ["name": name.trimmingCharacters(in: .whitespaces), "capacity": capacity.map { $0 as Any } ?? NSNull()]
        if !serverID.isEmpty { p["id"] = serverID }
        return p
    }
}

struct TicketEvent: Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var description: String = ""
    var startsAt: Date = TicketEvent.defaultStart
    var endsAt: Date = TicketEvent.defaultStart.addingTimeInterval(3 * 3600)
    var doorsAt: Date?
    var address: String = ""
    var lat: Double?
    var lng: Double?
    var capacity: Int = 100
    var maxPerPerson: Int = 4
    var signupUntil: Date?
    var waitlist: Bool = true
    var color: String?
    var headerURL: String?
    var status: String = "draft"
    var ticketTypes: [TicketType] = [TicketType(name: String(localized: "Toegang"))]
    var registered: Int = 0
    var checkedIn: Int = 0
    var waiting: Int = 0

    static var defaultStart: Date {
        let c = TKFormat.calendar
        let base = c.date(byAdding: .day, value: 14, to: .now) ?? .now
        return c.date(bySettingHour: 16, minute: 0, second: 0, of: base) ?? base
    }

    init() {}

    init?(json j: JSONObject) {
        guard let id = j.string("id", "event_id") else { return nil }
        self.id = id
        name = j.string("name") ?? ""
        description = j.string("description") ?? ""
        startsAt = j.date("starts_at") ?? .now
        endsAt = j.date("ends_at") ?? startsAt.addingTimeInterval(3 * 3600)
        doorsAt = j.date("doors_at")
        address = j.string("address") ?? ""
        lat = j.double("lat")
        lng = j.double("lng")
        capacity = j.int("capacity") ?? 0
        maxPerPerson = j.int("max_per_person") ?? 4
        signupUntil = j.date("signup_until")
        // "waitlist" is bij opslaan een ja/nee, in de lijst het aantal op de wachtlijst
        if let n = j.raw["waitlist"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
            waiting = n.intValue
            waitlist = j.bool("waitlist_enabled") ?? true
        } else {
            waitlist = j.bool("waitlist", "waitlist_enabled") ?? false
            waiting = j.int("waitlist_count", "waiting") ?? 0
        }
        color = j.string("color")
        headerURL = j.string("header_url")
        status = (j.string("status") ?? "draft").lowercased()
        let types: [JSONObject]
        if let s = j.raw["ticket_types"] as? String, let data = s.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            types = list.compactMap { JSONObject($0) }
        } else {
            types = j.array("ticket_types")
        }
        ticketTypes = types.map { TicketType(json: $0) }
        if ticketTypes.isEmpty { ticketTypes = [TicketType(name: String(localized: "Toegang"))] }
        registered = j.int("registered") ?? 0
        checkedIn = j.int("checked_in") ?? 0
    }

    var isPublished: Bool { status == "published" }
    var isCancelled: Bool { status == "cancelled" }
    var isPast: Bool { endsAt < .now }
    var addURL: URL { URL(string: "https://pasr.nl/add/e/\(id.lowercased())")! }
    var spotsLeft: Int { max(0, capacity - registered) }

    func payload(status newStatus: String) -> [String: Any] {
        var p: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces),
            "description": description,
            "starts_at": TKFormat.timestamp(startsAt),
            "ends_at": TKFormat.timestamp(endsAt),
            "doors_at": doorsAt.map { TKFormat.timestamp($0) as Any } ?? NSNull(),
            "address": address,
            "lat": lat.map { $0 as Any } ?? NSNull(),
            "lng": lng.map { $0 as Any } ?? NSNull(),
            "capacity": capacity,
            "max_per_person": maxPerPerson,
            "signup_until": signupUntil.map { TKFormat.timestamp($0) as Any } ?? NSNull(),
            "waitlist": waitlist,
            "color": color.map { $0 as Any } ?? NSNull(),
            "header_url": (headerURL?.isEmpty == false ? headerURL! : nil).map { $0 as Any } ?? NSNull(),
            "status": newStatus,
            "ticket_types": ticketTypes.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map(\.payload),
        ]
        if !id.isEmpty { p["id"] = id }
        return p
    }
}

struct EventRegistration: Identifiable, Hashable {
    var id: String
    var ticketID: String
    var firstName: String
    var lastName: String
    var email: String
    var birthDate: Date?
    var ticketType: String
    var status: String
    var createdAt: Date?
    var checkedInAt: Date?

    init(json j: JSONObject, index: Int) {
        ticketID = j.string("ticket_id") ?? ""
        id = (j.string("registration_id") ?? "r\(index)") + "-" + ticketID
        firstName = j.string("first_name") ?? ""
        lastName = j.string("last_name") ?? ""
        email = j.string("email") ?? ""
        birthDate = TKFormat.parseDay(j.string("birth_date"))
        ticketType = j.string("ticket_type") ?? ""
        status = (j.string("status") ?? "registered").lowercased()
        createdAt = j.date("created_at")
        checkedInAt = j.date("checked_in_at")
    }

    var fullName: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

struct TicketScan: Equatable {
    var code: String
    var result: String
    var firstName: String
    var lastName: String
    var ticketType: String
    var eventID: String?
    var eventName: String
    var checkedInAt: Date?
    var checkedIn: Int?
    var registered: Int?
    var capacity: Int?

    init?(json any: Any?, code: String) {
        guard let j = JSONObject(any), let result = j.string("result", "status") else { return nil }
        self.code = code
        self.result = result.lowercased()
        firstName = j.string("first_name") ?? ""
        lastName = j.string("last_name") ?? ""
        ticketType = j.string("ticket_type") ?? ""
        eventID = j.string("event_id")
        eventName = j.string("event_name") ?? ""
        checkedInAt = j.date("checked_in_at")
        let counts = j.object("counts")
        checkedIn = counts?.int("checked_in")
        registered = counts?.int("registered")
        capacity = counts?.int("capacity")
    }

    var isValid: Bool { result == "valid" }
    var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

// MARK: Klantenkaarten

struct DiscountPeriod: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var serverID: String?
    var label: String = ""
    var percent: Double = 10
    var startsOn: Date = TKFormat.calendar.startOfDay(for: .now)
    var endsOn: Date = TKFormat.calendar.date(byAdding: .day, value: 14, to: TKFormat.calendar.startOfDay(for: .now)) ?? .now
    /// 1 = ma … 7 = zo; leeg = elke dag.
    var weekdays: Set<Int> = []
    var fromTime: Date?
    var toTime: Date?

    init() {}

    init(json j: JSONObject) {
        serverID = j.string("id")
        if let serverID { id = serverID }
        label = j.string("label") ?? ""
        percent = j.double("percent") ?? 0
        startsOn = TKFormat.parseDay(j.string("starts_on")) ?? .now
        endsOn = TKFormat.parseDay(j.string("ends_on")) ?? startsOn
        weekdays = Set(j.ints("weekdays") ?? [])
        fromTime = TKFormat.parseTime(j.string("from_time"))
        toTime = TKFormat.parseTime(j.string("to_time"))
    }

    var payload: [String: Any] {
        var p: [String: Any] = [
            "label": label, "percent": percent,
            "starts_on": TKFormat.day(startsOn), "ends_on": TKFormat.day(endsOn),
            "weekdays": weekdays.isEmpty ? NSNull() as Any : weekdays.sorted() as Any,
            "from_time": fromTime.map { TKFormat.time($0) as Any } ?? NSNull(),
            "to_time": toTime.map { TKFormat.time($0) as Any } ?? NSNull(),
        ]
        if let serverID { p["id"] = serverID }
        return p
    }

    /// "1 dec – 15 dec · 15% · hele dag" / "Elke di 17:00–19:00 · 20%"
    var summary: String {
        let range = startsOn.formatted(.dateTime.day().month(.abbreviated)) + " – " + endsOn.formatted(.dateTime.day().month(.abbreviated))
        var parts = [range]
        if !weekdays.isEmpty { parts.append(TKWeekday.names(weekdays)) }
        if let fromTime, let toTime {
            parts.append(TKFormat.time(fromTime) + "–" + TKFormat.time(toTime))
        } else {
            parts.append(String(localized: "hele dag"))
        }
        parts.append(TKFormat.percent(percent) + "%")
        return parts.joined(separator: " · ")
    }
}

enum TKWeekday {
    /// Korte namen ma…zo in de taal van het toestel (1 = maandag).
    static func short(_ day: Int) -> String {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        guard symbols.count == 7, (1...7).contains(day) else { return "\(day)" }
        return symbols[day % 7]   // symbols[0] = zondag, 7 = zo
    }

    static func names(_ days: Set<Int>) -> String { days.sorted().map(short).joined(separator: ", ") }
}

struct MemberGoals: Hashable {
    var membership = true
    var savingEnabled = false
    var savingUnit = "visits"
    var savingTarget = 10
    var savingReward = ""
    var fixedEnabled = false
    var fixedPercent: Double = 10
    var periods: [DiscountPeriod] = []

    init() {}

    init(json j: JSONObject?) {
        guard let j else { return }
        membership = j.bool("membership") ?? false
        let s = j.object("saving")
        savingEnabled = s?.bool("enabled") ?? false
        savingUnit = s?.string("unit") ?? "visits"
        savingTarget = s?.int("target") ?? 10
        savingReward = s?.string("reward") ?? ""
        let f = j.object("fixed_discount")
        fixedEnabled = f?.bool("enabled") ?? false
        fixedPercent = f?.double("percent") ?? 10
        periods = j.array("periods").map { DiscountPeriod(json: $0) }
    }

    var payload: [String: Any] {
        [
            "membership": membership,
            "saving": ["enabled": savingEnabled, "unit": savingUnit, "target": savingTarget, "reward": savingReward],
            "fixed_discount": ["enabled": fixedEnabled, "percent": fixedPercent],
            "periods": periods.map(\.payload),
        ]
    }
}

struct DiscountInfo: Hashable {
    var percent: Double
    var label: String
    var until: Date?
    var startsAt: Date?

    init?(json j: JSONObject?) {
        guard let j, let p = j.double("percent") else { return nil }
        percent = p
        label = j.string("label") ?? ""
        until = j.date("until", "ends_at")
        startsAt = j.date("starts_at")
    }
}

struct SavingInfo: Hashable {
    var count: Int
    var target: Int
    var reward: String
    var canRedeem: Bool
    var unit: String?

    init?(json j: JSONObject?) {
        guard let j else { return nil }
        count = j.int("count") ?? 0
        target = max(1, j.int("target") ?? 10)
        reward = j.string("reward") ?? ""
        canRedeem = j.bool("can_redeem") ?? (count >= target)
        unit = j.string("unit")
    }
}

struct MemberCard: Identifiable, Hashable {
    var id: String = ""
    var name: String = ""
    var color: String = "#7B4B2A"
    var logo: String?
    var barcodeType: String = "code128"
    var prefix: String = ""
    var status: String = "draft"
    var members: Int = 0
    var goals = MemberGoals()
    var discountNow: DiscountInfo?
    var nextDiscount: DiscountInfo?

    init() {}

    init?(json j: JSONObject) {
        guard let id = j.string("id", "card_id") else { return nil }
        self.id = id
        name = j.string("name") ?? ""
        color = j.string("color") ?? "#7B4B2A"
        logo = j.string("logo")
        barcodeType = (j.string("barcode_type") ?? "code128").lowercased()
        prefix = j.string("prefix") ?? ""
        status = (j.string("status") ?? "draft").lowercased()
        members = j.int("members", "members_count") ?? 0
        goals = MemberGoals(json: j.object("goals"))
        discountNow = DiscountInfo(json: j.object("discount_now"))
        nextDiscount = DiscountInfo(json: j.object("next_discount"))
    }

    var isPublished: Bool { status == "published" }
    var addURL: URL { URL(string: "https://pasr.nl/add/m/\(id.lowercased())")! }

    func payload(status newStatus: String, logoChanged: Bool) -> [String: Any] {
        var p: [String: Any] = [
            "name": name.trimmingCharacters(in: .whitespaces), "color": color.uppercased(),
            "barcode_type": barcodeType, "prefix": barcodeType == "ean13" ? "" : prefix,
            "status": newStatus, "goals": goals.payload,
        ]
        if !id.isEmpty { p["id"] = id }
        if logoChanged || id.isEmpty { p["logo"] = logo.map { $0 as Any } ?? NSNull() }
        return p
    }

    /// Voorbeeldnummer voor de kaart in beeld.
    var sampleNumber: String {
        barcodeType == "ean13" ? "8712345000124" : (prefix.isEmpty ? "000124" : prefix + "000124")
    }
}

struct MemberScan: Equatable {
    var code: String
    var result: String
    var cardID: String?
    var cardName: String
    var memberName: String?
    var number: String
    var discountNow: DiscountInfo?
    var nextDiscount: DiscountInfo?
    var saving: SavingInfo?

    init?(json any: Any?, code: String) {
        guard let j = JSONObject(any), let result = j.string("result", "status") else { return nil }
        self.code = code
        self.result = result.lowercased()
        cardID = j.string("card_id")
        cardName = j.string("card_name") ?? ""
        memberName = j.string("member_name")
        number = j.string("number") ?? code
        discountNow = DiscountInfo(json: j.object("discount_now"))
        nextDiscount = DiscountInfo(json: j.object("next_discount"))
        saving = SavingInfo(json: j.object("saving"))
    }

    var isValid: Bool { result == "valid" }
}

// MARK: Databasefuncties

@MainActor
enum TKAPI {
    private static var account: Account { .shared }

    private static func rows(_ json: Any) -> [JSONObject] {
        if let list = json as? [Any] { return list.compactMap { JSONObject($0) } }
        guard let j = JSONObject(json) else { return [] }
        let inner = j.array("events", "cards", "registrations", "rows", "items")
        return inner
    }

    private static func id(of json: Any) -> String? {
        if let s = json as? String { return s }
        return JSONObject(json)?.string("id", "event_id", "card_id")
    }

    // Tickets

    static func events(business: String) async throws -> [TicketEvent] {
        let json = try await account.rpc("pasr_business_events", ["p_business": business])
        return rows(json).compactMap { TicketEvent(json: $0) }.sorted { $0.startsAt < $1.startsAt }
    }

    @discardableResult
    static func saveEvent(_ event: TicketEvent, business: String, status: String) async throws -> String? {
        let json = try await account.rpc("pasr_business_event_save", ["p_business": business, "p_event": event.payload(status: status)])
        return id(of: json)
    }

    static func registrations(business: String, event: String) async throws -> [EventRegistration] {
        let json = try await account.rpc("pasr_business_event_registrations", ["p_business": business, "p_event": event])
        return rows(json).enumerated().map { EventRegistration(json: $0.element, index: $0.offset) }
    }

    static func cancelEvent(business: String, event: String, message: String) async throws {
        _ = try await account.rpc("pasr_business_event_cancel", ["p_business": business, "p_event": event, "p_message": message])
    }

    static func scanTicket(business: String, code: String, event: String?) async throws -> TicketScan {
        let json = try await account.rpc("pasr_business_ticket_scan",
                                          ["p_business": business, "p_code": code, "p_event": event.map { $0 as Any } ?? NSNull()])
        guard let r = TicketScan(json: json, code: code) else { throw APIError(String(localized: "Dit ticket is niet bekend.")) }
        return r
    }

    // Klantenkaarten

    static func memberCards(business: String) async throws -> [MemberCard] {
        let json = try await account.rpc("pasr_business_member_cards", ["p_business": business])
        return rows(json).compactMap { MemberCard(json: $0) }
    }

    @discardableResult
    static func saveMemberCard(_ card: MemberCard, business: String, status: String, logoChanged: Bool) async throws -> String? {
        let json = try await account.rpc("pasr_business_member_card_save",
                                          ["p_business": business, "p_card": card.payload(status: status, logoChanged: logoChanged)])
        return id(of: json)
    }

    static func scanMemberCard(business: String, code: String) async throws -> MemberScan {
        let json = try await account.rpc("pasr_business_member_card_scan", ["p_business": business, "p_code": code])
        guard let r = MemberScan(json: json, code: code) else { throw APIError(String(localized: "Deze klantenkaart is niet bekend.")) }
        return r
    }

    static func visit(business: String, code: String, points: Int?) async throws -> SavingInfo? {
        var args: [String: Any] = ["p_business": business, "p_code": code]
        if let points { args["p_points"] = points }
        let json = try await account.rpc("pasr_business_member_card_visit", args)
        let j = JSONObject(json)
        return SavingInfo(json: j?.object("saving") ?? j)
    }

    static func redeem(business: String, code: String) async throws -> SavingInfo? {
        let json = try await account.rpc("pasr_business_member_card_redeem", ["p_business": business, "p_code": code])
        let j = JSONObject(json)
        return SavingInfo(json: j?.object("saving") ?? j)
    }
}

/// Wat de camera of het toetsenbord oplevert, ingedeeld naar soort code.
enum ScanCode: Equatable {
    case coupon(String)
    case stampCard(String)
    case ticket(String)
    case memberCard(String)

    static func classify(_ text: String) -> ScanCode? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        // link van een ticket: https://pasr.nl/add/t/<ticket>?c=<code>
        if let url = URL(string: t), url.scheme != nil {
            if url.path().contains("/add/t/"),
               let c = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "c" })?.value,
               !c.isEmpty {
                return .ticket(c)
            }
            return MemberCode.extract(t).map { .stampCard($0) }
        }
        let upper = t.uppercased()
        if upper.range(of: "^PC[A-HJ-NP-Z2-9]{22}$", options: .regularExpression) != nil { return .coupon(upper) }
        let compact = upper.replacingOccurrences(of: " ", with: "")
        if compact.range(of: "^PZ[A-HJ-NP-Z2-9]{10,40}$", options: .regularExpression) != nil { return .stampCard(compact) }
        if compact.range(of: "^[0-9]{13}$", options: .regularExpression) != nil { return .memberCard(compact) }
        // ticketcode: willekeurig, base32, minstens 20 tekens, zonder voorvoegsel
        if compact.range(of: "^[A-Z2-7]{20,64}$", options: .regularExpression) != nil { return .ticket(t.replacingOccurrences(of: " ", with: "")) }
        // klantenkaartnummer: voorvoegsel + nummer (KS-000124), kort
        if t.count <= 32, t.range(of: "^[A-Za-z0-9][A-Za-z0-9 ._/-]*[0-9]$", options: .regularExpression) != nil,
           t.range(of: "[0-9]", options: .regularExpression) != nil, !compact.hasPrefix("PZ") {
            return .memberCard(t)
        }
        return MemberCode.extract(t).map { .stampCard($0) }
    }
}
