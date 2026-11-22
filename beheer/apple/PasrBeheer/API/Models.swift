import Foundation

struct LoginResponse: Decodable {
    let token: String
    let expires: String
}

struct OKResponse: Decodable {
    let ok: Bool?
}

/// Antwoord van `stats` (databasefunctie pasr_admin_stats).
struct Stats: Decodable {
    struct Totals: Decodable {
        var accounts = 0, confirmed = 0, unconfirmed = 0, with_cards = 0, cards = 0
        var active_30d = 0, new_today = 0, new_7d = 0, new_30d = 0
    }
    struct Range: Decodable {
        let days: Int
        let offset: Int
        let from: String
        let to: String
    }
    struct Day: Decodable, Identifiable {
        let day: String
        var signups = 0, confirmed = 0, deleted = 0, expired = 0, wallet = 0, bots = 0
        var groups: Int? = nil
        var temp_shares: Int? = nil
        var accounts: Int? = nil
        var cards: Int? = nil
        var id: String { day }
        var date: Date { DateParse.day(day) ?? .distantPast }

        func value(_ m: Metric) -> Int? {
            switch m {
            case .accounts: accounts
            case .signups: signups
            case .confirmed: confirmed
            case .deleted: deleted
            case .cards: cards
            case .wallet: wallet
            case .bots: bots
            case .groups: groups ?? 0
            case .tempShares: temp_shares ?? 0
            }
        }
    }

    /// Gedeelde Pasrs (groepen van maximaal 6 accounts).
    struct Shared: Decodable {
        var groups = 0, members = 0, people = 0, cards = 0, invites = 0, new_7d = 0
    }
    /// Tijdelijk gedeelde kaarten.
    struct Temp: Decodable {
        var active = 0, opens = 0, revoked_30d = 0, new_7d = 0
    }

    let generated: String?
    let totals: Totals
    let wallet_total: Int
    let range: Range
    let per_day: [Day]
    let bots_7d: [String: Int]
    let signups_allowed_7d: Int
    let cards_per_account: [String: Int]
    let push_devices: Int
    let push_ready: Bool?
    var countries: [String: Int]? = nil
    var shared: Shared? = nil
    var temp: Temp? = nil
}

/// Bronnen in Insights (zoals Homey Insights): lijnen voor totalen, staven voor aantallen per dag.
enum Metric: String, CaseIterable, Identifiable, Codable {
    case accounts, signups, confirmed, deleted, cards, wallet, groups, tempShares, bots
    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts: "Accounts"
        case .signups: "Nieuwe accounts"
        case .confirmed: "Bevestigd"
        case .deleted: "Verwijderd"
        case .cards: "Kaarten in accounts"
        case .wallet: "Wallet-passen"
        case .groups: "Gedeelde Pasrs"
        case .tempShares: "Tijdelijk gedeeld"
        case .bots: "Bots tegengehouden"
        }
    }

    var detail: String {
        switch self {
        case .accounts: "totaal aan het eind van de dag"
        case .signups: "aangemaakt"
        case .confirmed: "e-mailadres bevestigd"
        case .deleted: "door de gebruiker zelf"
        case .cards: "totaal (elk uur gemeten)"
        case .wallet: "gemaakt"
        case .groups: "nieuw gemaakt"
        case .tempShares: "kaarten tijdelijk gedeeld"
        case .bots: "aanmeldingen geweigerd"
        }
    }

    var isLine: Bool { self == .accounts || self == .cards }
}

struct UsersResponse: Decodable {
    let total: Int
    let users: [User]
}

struct User: Decodable, Identifiable, Hashable {
    let id: String
    let email: String?
    let first_name: String?
    var country: String? = nil
    let created_at: String?
    let email_confirmed_at: String?
    let last_sign_in_at: String?
    let cards: Int
    var groups: Int? = nil
    let synced_at: String?

    var isConfirmed: Bool { email_confirmed_at != nil }
    var initial: String { String((first_name ?? email ?? "?").trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
}

/// Winkelaanvragen uit de app, gebundeld per winkel (store_requests).
struct StoreRequestGroup: Decodable, Identifiable, Hashable {
    let key: String
    let name: String
    let website: String?
    var kind: String? = nil
    let count: Int
    let ids: [String]
    let notes: [String]
    let first: String
    let last: String
    var id: String { key }
}
struct StoreRequestsResponse: Decodable { let groups: [StoreRequestGroup] }

/// Een winkel die via het beheer is toegevoegd (pasr_stores).
struct RemoteStore: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var domain: String
    var category: String
    var card_hex: String
    var format: String
    var kind: String
    var aliases: [String]
    var logo: String?
    var published: Bool
    var updated_at: String?
    /// Cadeaubon-gids (cadeaukaart) of programmagids (klantenkaart); kolom pasr_stores.guide.
    var guide: StoreGuide? = nil
    /// Kaartontwerp (voorkant) van een cadeaukaart: base64 JPEG/PNG, 1,586:1.
    var cover: String? = nil

    var isVoucher: Bool { kind == "voucher" }
    /// Sleutel voor de afbeeldingencache: verandert zodra de winkel is opgeslagen.
    func imageKey(_ part: String) -> String { "\(id)|\(updated_at ?? "")|\(part)" }
}

/// Gids bij een winkel. Alle velden optioneel; dezelfde sleutels en grenzen als cleanGuide in supabase/functions/admin/stores.ts.
/// Lezen is vergevingsgezind: een onverwacht veld of type maakt de hele winkellijst niet onleesbaar.
struct StoreGuide: Codable, Hashable {
    // cadeaukaart
    var validity: String?
    var online: Bool?
    var store: Bool?
    var shipping: String?
    // klantenkaart
    var earn: String?
    var perks: String?
    var program_url: String?
    // beide
    var how: String?
    var terms_url: String?
    var checked: String?
    /// Verjaardagsvoordeel (1.0.3), alleen als de officiële site het noemt.
    var birthday: String?

    init() {}

    private enum K: String, CodingKey { case validity, online, store, shipping, earn, perks, program_url, how, terms_url, checked, birthday }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: K.self) else { return }
        func s(_ k: K) -> String? { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil }
        func b(_ k: K) -> Bool? { (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? nil }
        validity = s(.validity); online = b(.online); store = b(.store); shipping = s(.shipping)
        earn = s(.earn); perks = s(.perks); program_url = s(.program_url)
        how = s(.how); terms_url = s(.terms_url); checked = s(.checked); birthday = s(.birthday)
    }

    var isEmpty: Bool { self == StoreGuide() }

    /// Als JSON-object voor store_save (alleen ingevulde velden).
    var json: [String: Any] {
        var d: [String: Any] = [:]
        if let validity { d["validity"] = validity }
        if let online { d["online"] = online }
        if let store { d["store"] = store }
        if let shipping { d["shipping"] = shipping }
        if let earn { d["earn"] = earn }
        if let perks { d["perks"] = perks }
        if let program_url { d["program_url"] = program_url }
        if let how { d["how"] = how }
        if let terms_url { d["terms_url"] = terms_url }
        if let checked { d["checked"] = checked }
        if let birthday { d["birthday"] = birthday }
        return d
    }
}
struct StoresResponse: Decodable { let stores: [RemoteStore] }
struct StoreSaveResponse: Decodable { let store: RemoteStore }
struct StorePublishResponse: Decodable { let ok: Bool; let sent: Int; let closed: Int; let push_ready: Bool? }
struct StoreLookup: Decodable { let domain: String; let name: String?; let colors: [String]; let logo: String?; let logo_type: String? }

/// Tijdstempels uit Postgres ("2026-11-01T14:28:35.925497+00:00") en dagen ("2026-11-01").
enum DateParse {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ s: String?) -> Date? {
        guard var s, !s.isEmpty else { return nil }
        // fractie van seconden weg (ISO8601DateFormatter kent er hoogstens drie)
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) { s.removeSubrange(r) }
        if s.hasSuffix("+00") { s += ":00" }
        return iso.date(from: s)
    }

    static func day(_ s: String) -> Date? { dayFormatter.date(from: s) }
}

// MARK: Berichten (gerichte push, 1.0.3)

struct NewsOverview: Decodable {
    struct StoreCount: Decodable, Hashable { let id: String; let count: Int }
    let all: Int
    let new: Int
    let inactive: Int
    let stores: [StoreCount]
    let history: [NewsCampaign]
    let push_ready: Bool?
}
struct NewsCampaign: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let body: String
    let audience: String
    let store_id: String?
    let recipients: Int
    let sent: Int
    let failed: Int
    let created_at: String
}
struct NewsCount: Decodable { let count: Int }
struct NewsSendResponse: Decodable { let id: String; let recipients: Int; let sent: Int; let failed: Int }

/// Doelgroepen van "Bericht sturen" (zelfde sleutels als supabase/functions/admin/news.ts).
enum NewsAudience: String, CaseIterable, Identifiable {
    case all, store, new, inactive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Iedereen met opt-in"
        case .store: "Heeft een kaart van"
        case .new: "Nieuwe gebruikers (7 dagen)"
        case .inactive: "Inactief (30 dagen)"
        }
    }
}

// MARK: Ondernemers (Pasr voor ondernemers, 1.0.3)

struct BusinessCard: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let logo: String?
    let color: String
    let stamps_total: Int
    let reward: String
    let published: Bool?
    let members: Int?
    let stamps: Int?
    let rewards: Int?
    let updated_at: String?
}
struct Business: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let city: String?
    let email: String?
    let website: String?
    let note: String?
    let status: String
    let created_at: String?
    let reviewed_at: String?
    let cards: [BusinessCard]
    // zakelijk 1.0
    let cooldown_minutes: Int?
    let max_per_scan: Int?
    let listed: Bool?
    let address: String?
    let lat: Double?
    let lng: Double?
    let staff_count: Int?
    let last_event_at: String?

    var statusTitle: String {
        switch status {
        case "approved": "Goedgekeurd"
        case "blocked": "Geblokkeerd"
        default: "Wacht op goedkeuring"
        }
    }
}
struct BusinessesResponse: Decodable { let businesses: [Business] }

// MARK: Ondernemers: details per zaak (zakelijk 1.0, actie business_detail)

/// Zaak zonder kaarten (zoals business_detail hem geeft).
struct BusinessInfo: Decodable, Hashable {
    let id: String
    let name: String
    let status: String
    let cooldown_minutes: Int?
    let max_per_scan: Int?
    let listed: Bool?
    let address: String?
    let lat: Double?
    let lng: Double?
}
struct BusinessStaff: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let email: String?
    let role: String
    let created_at: String?
    let accepted_at: String?
    let pending: Bool?
    let expired: Bool?
    let revoked: Bool?

    var statusTitle: String {
        if revoked == true { return "ingetrokken" }
        if pending == true { return expired == true ? "uitnodiging verlopen" : "uitnodiging open" }
        return "actief"
    }
}
struct BusinessEvent: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let amount: Int?
    let at: String
    let card_name: String?
    let member_suffix: String?
    let by_name: String?
    let by_role: String?
    let device: String?
    let stamps_before: Int?
    let stamps_after: Int?
    let undone: Bool?

    var title: String {
        switch kind {
        case "stamp": return (amount ?? 1) == 1 ? "1 stempel" : "\(amount ?? 1) stempels"
        case "redeem": return "Beloning ingewisseld"
        case "undo": return "Ongedaan gemaakt"
        case "join": return "Nieuw lid"
        case "claim": return "Kaart naar de app"
        default: return kind
        }
    }
}
struct BusinessDay: Decodable, Identifiable, Hashable {
    let day: String
    let stamps: Int
    let rewards: Int
    let new_members: Int
    var id: String { day }
}
struct BusinessTotals: Decodable, Hashable {
    let stamps: Int
    let rewards: Int
    let new_members: Int
    let members: Int
}
struct BusinessStats: Decodable, Hashable {
    let days: [BusinessDay]
    let totals: BusinessTotals
}
struct BusinessDetail: Decodable {
    let business: BusinessInfo
    let staff: [BusinessStaff]
    let log: [BusinessEvent]
    let stats: BusinessStats
}
