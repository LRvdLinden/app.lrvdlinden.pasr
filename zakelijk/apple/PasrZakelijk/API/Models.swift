import Foundation

enum BusinessRole: String {
    case owner, staff
}

enum BusinessStatus: String {
    case pending, approved, blocked
}

/// Een stempelkaart van de zaak.
struct BusinessCard: Identifiable, Hashable {
    var id: String
    var name: String
    var logo: String?
    var color: String
    var stampsTotal: Int
    var reward: String
    var published: Bool
    var members: Int
    var stamps: Int
    var rewards: Int

    init(id: String = "", name: String = "", logo: String? = nil, color: String = "#6A5CFF", stampsTotal: Int = 10,
         reward: String = "", published: Bool = false, members: Int = 0, stamps: Int = 0, rewards: Int = 0) {
        self.id = id; self.name = name; self.logo = logo; self.color = color; self.stampsTotal = stampsTotal
        self.reward = reward; self.published = published; self.members = members; self.stamps = stamps; self.rewards = rewards
    }

    init?(json j: JSONObject) {
        guard let id = j.string("id", "card_id") else { return nil }
        self.init(id: id, name: j.string("name") ?? "", logo: j.string("logo"), color: j.string("color") ?? "#6A5CFF",
                  stampsTotal: j.int("stamps_total") ?? 10, reward: j.string("reward") ?? "",
                  published: j.bool("published") ?? false, members: j.int("members", "members_count") ?? 0,
                  stamps: j.int("stamps") ?? 0, rewards: j.int("rewards") ?? 0)
    }

    /// Link en QR-code waarmee klanten zich aanmelden.
    var joinURL: URL { URL(string: "https://pasr.nl/zakelijk/kaart/#\(id)")! }
}

/// Een zaak waar je eigenaar of medewerker van bent.
struct Business: Identifiable, Hashable {
    var id: String
    var name: String
    var city: String
    var email: String
    var website: String?
    var note: String?
    var status: BusinessStatus
    var role: BusinessRole
    var cooldownMinutes: Int
    var maxPerScan: Int
    /// Vindbaar in de lijst met stempelkaarten in Pasr (standaard aan), met adres en plek voor "In de buurt".
    var listed: Bool
    var address: String
    var lat: Double?
    var lng: Double?
    var cards: [BusinessCard]

    var isOwner: Bool { role == .owner }
    var isApproved: Bool { status == .approved }

    /// Leest zowel {business:{…}, cards:[…], role} als een platte zaak met role en cards.
    init?(json j: JSONObject, fallbackRole: BusinessRole = .owner) {
        let b = j.object("business") ?? j
        guard let id = b.string("id", "business_id") else { return nil }
        self.id = id
        name = b.string("name", "business_name") ?? ""
        city = b.string("city") ?? ""
        email = b.string("email") ?? ""
        website = b.string("website")
        note = b.string("note")
        status = BusinessStatus(rawValue: (b.string("status") ?? j.string("status") ?? "pending").lowercased()) ?? .pending
        role = BusinessRole(rawValue: (j.string("role") ?? b.string("role") ?? fallbackRole.rawValue).lowercased()) ?? fallbackRole
        let settings = j.object("settings") ?? b.object("settings")
        cooldownMinutes = j.int("cooldown_minutes") ?? b.int("cooldown_minutes") ?? settings?.int("cooldown_minutes") ?? 5
        maxPerScan = j.int("max_per_scan") ?? b.int("max_per_scan") ?? settings?.int("max_per_scan") ?? 10
        listed = j.bool("listed") ?? b.bool("listed") ?? settings?.bool("listed") ?? true
        address = j.string("address") ?? b.string("address") ?? settings?.string("address") ?? ""
        lat = (j.raw["lat"] ?? b.raw["lat"]) as? Double
        lng = (j.raw["lng"] ?? b.raw["lng"]) as? Double
        let list = j.array("cards").isEmpty ? b.array("cards") : j.array("cards")
        cards = list.compactMap { BusinessCard(json: $0) }
    }
}

/// Wat de scanner over een klantcode weet.
struct ScanResult: Equatable {
    var code: String
    var suffix: String
    var business: String?
    var cardName: String
    var color: String
    var logo: String?
    var stampsTotal: Int
    var reward: String
    var stamps: Int
    var rewardsRedeemed: Int
    var lastStampAt: Date?
    var cooldownUntil: Date?
    /// Id van het laatste stempel/inwisseling dat nog ongedaan kan (bij scannen) of van de actie die je net deed.
    var undoEventID: String?
    var maxPerScan: Int?
    var canRedeem: Bool?

    var isFull: Bool { canRedeem ?? (stamps >= stampsTotal) }

    init?(json any: Any?, code: String) {
        guard let j = JSONObject(any) else { return nil }
        if let status = j.string("status"), status != "ok", !j.has("card"), !j.has("stamps") { return nil }
        let card = j.object("card")
        self.code = code
        suffix = j.string("member_code_suffix", "suffix") ?? String((j.string("member_code") ?? code).suffix(4))
        business = card?.string("business") ?? j.string("business", "business_name")
        cardName = card?.string("name") ?? j.string("name", "card_name") ?? ""
        color = card?.string("color") ?? j.string("color") ?? "#6A5CFF"
        logo = card?.string("logo") ?? j.string("logo")
        stampsTotal = card?.int("stamps_total") ?? j.int("stamps_total") ?? 10
        reward = card?.string("reward") ?? j.string("reward") ?? ""
        stamps = j.int("stamps", "stamps_count") ?? 0
        rewardsRedeemed = j.int("rewards_redeemed") ?? 0
        lastStampAt = j.date("last_stamp_at")
        cooldownUntil = j.date("cooldown_until")
        // na stempelen/inwisselen is event_id de nieuwe actie; bij scannen geeft can_undo_event_id de laatste
        undoEventID = j.has("can_undo_event_id") ? j.string("can_undo_event_id") : j.string("event_id")
        if j.has("undone") { undoEventID = j.string("can_undo_event_id") }
        maxPerScan = j.int("max_per_scan")
        canRedeem = j.bool("can_redeem")
    }
}

/// Medewerker (of eigenaar) van een zaak.
struct StaffMember: Identifiable, Hashable {
    var id: String
    var name: String
    var email: String
    var role: BusinessRole
    var createdAt: Date?
    var revoked: Bool
    var pending: Bool
    var expired: Bool

    init?(json j: JSONObject) {
        guard let id = j.string("id", "staff_id") else { return nil }
        self.id = id
        name = j.string("name") ?? ""
        email = j.string("email", "invited_email") ?? ""
        role = BusinessRole(rawValue: (j.string("role") ?? "staff").lowercased()) ?? .staff
        createdAt = j.date("created_at")
        revoked = j.bool("revoked") ?? j.has("revoked_at")
        pending = j.bool("pending") ?? false
        expired = j.bool("expired") ?? false
    }
}

/// Uitnodiging: code en link om te delen.
struct StaffInvite: Identifiable {
    var code: String
    var link: URL
    var id: String { code }

    init?(json any: Any?) {
        guard let j = JSONObject(any), let code = j.string("invite_code", "code") else { return nil }
        self.code = code
        link = j.string("link", "url").flatMap(URL.init(string:)) ?? URL(string: "https://pasr.nl/zakelijk/uitnodiging/#\(code)")!
    }
}

/// Eén regel uit het logboek.
struct LogEvent: Identifiable, Hashable {
    var id: String
    var kind: String
    var amount: Int
    var at: Date?
    var who: String
    var card: String
    var member: String
    var device: String?
    var byRole: String
    var undone: Bool

    init?(json j: JSONObject) {
        kind = (j.string("kind", "type") ?? "").lowercased()
        id = j.string("id", "event_id") ?? UUID().uuidString
        amount = j.int("amount") ?? 1
        at = j.date("at", "created_at")
        who = j.string("by_name", "who", "staff_name", "by_email", "email") ?? ""
        card = j.string("card", "card_name") ?? (j.object("card")?.string("name") ?? "")
        member = j.string("member_suffix", "member_code_suffix", "member", "code") ?? ""
        device = j.string("device")
        byRole = j.string("by_role") ?? ""
        undone = j.bool("undone") ?? false
    }
}

/// Cijfers van één dag.
struct DayStat: Identifiable, Hashable {
    var day: Date
    var stamps: Int
    var rewards: Int
    var joins: Int
    var id: Date { day }

    init?(json j: JSONObject) {
        guard let day = j.date("day", "date") else { return nil }
        self.day = day
        stamps = j.int("stamps") ?? 0
        rewards = j.int("rewards", "redeems") ?? 0
        joins = j.int("joins", "new_members", "members") ?? 0
    }

    init(day: Date, stamps: Int = 0, rewards: Int = 0, joins: Int = 0) {
        self.day = day; self.stamps = stamps; self.rewards = rewards; self.joins = joins
    }
}

/// Lid van een kaart (alleen de laatste tekens van de code).
struct MemberRow: Identifiable, Hashable {
    var id: String
    var code: String
    var stamps: Int
    var rewards: Int
    var createdAt: Date?
    var lastStampAt: Date?
    var app: Bool

    init(json j: JSONObject, index: Int) {
        code = j.string("code", "member_code_suffix") ?? "…"
        id = "\(index)-\(code)"
        stamps = j.int("stamps_count", "stamps") ?? 0
        rewards = j.int("rewards_redeemed", "rewards") ?? 0
        createdAt = j.date("created_at")
        lastStampAt = j.date("last_stamp_at")
        app = j.bool("app") ?? false
    }
}
