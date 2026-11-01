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
        var id: String { day }
        var date: Date { DateParse.day(day) ?? .distantPast }

        func value(_ s: Series) -> Int {
            switch s {
            case .signups: signups
            case .confirmed: confirmed
            case .deleted: deleted
            case .wallet: wallet
            case .bots: bots
            }
        }
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
}

/// Reeksen in de grafiek.
enum Series: String, CaseIterable, Identifiable {
    case signups, confirmed, deleted, wallet, bots
    var id: String { rawValue }

    var title: String {
        switch self {
        case .signups: "Nieuwe accounts"
        case .confirmed: "Bevestigd"
        case .deleted: "Verwijderd"
        case .wallet: "Wallet-passen"
        case .bots: "Bots"
        }
    }
}

struct UsersResponse: Decodable {
    let total: Int
    let users: [User]
}

struct User: Decodable, Identifiable, Hashable {
    let id: String
    let email: String?
    let first_name: String?
    let created_at: String?
    let email_confirmed_at: String?
    let last_sign_in_at: String?
    let cards: Int
    let synced_at: String?

    var isConfirmed: Bool { email_confirmed_at != nil }
    var initial: String { String((first_name ?? email ?? "?").trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
}

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
