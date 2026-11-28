import Foundation
import LocalAuthentication
import SwiftUI

/// Onderdelen (zijbalk op iPad en Mac; op de iPhone vijf tabs: Vandaag, Mensen, Berichten, Cijfers en Meer).
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview, accounts, businesses, stores, supportMail, news, ownersMail, insights, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Vandaag"
        case .accounts: "Gebruikers"
        case .businesses: "Ondernemers"
        case .stores: "Winkelcatalogus"
        case .supportMail: "Postvak Support"
        case .news: "Pushberichten"
        case .ownersMail: "Postvak Ondernemers"
        case .insights: "Inzichten"
        case .settings: "Instellingen"
        }
    }

    var icon: String {
        switch self {
        case .overview: "house"
        case .accounts: "person.2"
        case .businesses: "storefront"
        case .stores: "rectangle.stack"
        case .supportMail: "tray"
        case .news: "bell"
        case .ownersMail: "tray.full"
        case .insights: "chart.xyaxis.line"
        case .settings: "gearshape"
        }
    }

    /// Kop in de zijbalk (nil: geen kop).
    static let groups: [(title: String?, items: [AppSection])] = [
        (nil, [.overview]),
        ("Mensen", [.accounts, .businesses]),
        ("Inhoud", [.stores]),
        ("Support (support@pasr.nl)", [.supportMail, .news]),
        ("Ondernemers (zakelijk@pasr.nl)", [.ownersMail]),
        ("Cijfers", [.insights]),
        (nil, [.settings]),
    ]

    /// Het postvak dat bij dit onderdeel hoort.
    var mailbox: MailBrand? {
        switch self {
        case .supportMail: MailBrand.pasr
        case .ownersMail: MailBrand.zakelijk
        default: nil
        }
    }
}

/// De vijf tabs op de iPhone.
enum PhoneTab: String, CaseIterable, Identifiable {
    case today, people, messages, figures, more
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Vandaag"
        case .people: "Mensen"
        case .messages: "Berichten"
        case .figures: "Cijfers"
        case .more: "Meer"
        }
    }

    var icon: String {
        switch self {
        case .today: "house"
        case .people: "person.2"
        case .messages: "envelope"
        case .figures: "chart.xyaxis.line"
        case .more: "ellipsis.circle"
        }
    }

    init(_ s: AppSection) {
        switch s {
        case .overview: self = .today
        case .accounts, .businesses: self = .people
        case .supportMail, .ownersMail: self = .messages
        case .insights: self = .figures
        case .stores, .news, .settings: self = .more
        }
    }

    var firstSection: AppSection {
        switch self {
        case .today: .overview
        case .people: .accounts
        case .messages: .supportMail
        case .figures: .insights
        case .more: .stores
        }
    }
}

/// Inlogsessie (token in de sleutelhanger), vergrendeling met Face ID / Touch ID en gedeelde toestand.
@MainActor
final class Session: ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var expiresAt: Date?
    @Published var loginMessage: String?
    @Published var section: AppSection = .overview
    @Published private(set) var refreshTick = 0
    /// Ongelezen mails in het postvak Support (badge) en in het postvak Ondernemers.
    @Published var mailUnread = 0
    @Published var mailUnreadOwners = 0

    /// Vergrendelen met Face ID / Touch ID (standaard aan).
    @Published var lockEnabled: Bool { didSet { UserDefaults.standard.set(lockEnabled, forKey: Self.lockKey) } }
    @Published private(set) var isLocked = false
    var autoUnlockTried = false

    private let api = AdminAPI()
    private var backgroundSince: Date?
    private static let keychainAccount = "session"
    private static let lockKey = "lockEnabled"

    /// iPhone/iPad: elke keer vergrendelen als de app op de achtergrond was. Mac: na 5 minuten niet voorop.
    #if os(macOS)
    static let lockAfter: TimeInterval = 5 * 60
    #else
    static let lockAfter: TimeInterval = 0
    #endif

    var isSignedIn: Bool { token != nil }

    init() {
        UserDefaults.standard.register(defaults: [Self.lockKey: true])
        lockEnabled = UserDefaults.standard.bool(forKey: Self.lockKey)
        if let data = Keychain.read(Self.keychainAccount),
           let stored = try? JSONDecoder().decode(StoredToken.self, from: data), stored.expires > .now {
            token = stored.token
            expiresAt = stored.expires
        } else {
            Keychain.delete(Self.keychainAccount)
        }
        isLocked = isSignedIn && lockEnabled && canLock
    }

    private struct StoredToken: Codable {
        let token: String
        let expires: Date
    }

    // MARK: inloggen

    func login(user: String, password: String) async throws {
        let r = try await api.send("login", token: nil, params: ["user": user, "password": password], as: LoginResponse.self)
        let exp = DateParse.date(r.expires) ?? Date.now.addingTimeInterval(12 * 3600)
        if let data = try? JSONEncoder().encode(StoredToken(token: r.token, expires: exp)) {
            Keychain.write(Self.keychainAccount, data)
        }
        token = r.token
        expiresAt = exp
        loginMessage = nil
        isLocked = false
        section = .overview
        PushService.shared.didSignIn()
    }

    func logout(_ message: String? = nil) {
        PushService.shared.signOut(token: token)
        Keychain.delete(Self.keychainAccount)
        token = nil
        expiresAt = nil
        isLocked = false
        loginMessage = message
        mailUnread = 0
        mailUnreadOwners = 0
        MailDrafts.shared.reset()
    }

    func logoutAll() async throws {
        try await api.raw("logout_all", token: token)
        PushService.shared.forget()
        logout("Je bent overal uitgelogd.")
    }

    /// Actie met het token; bij 401 terug naar inloggen.
    func call<T: Decodable>(_ action: String, _ params: [String: Any] = [:], as type: T.Type, timeout: TimeInterval = 45) async throws -> T {
        if let exp = expiresAt, exp <= .now {
            logout("Je sessie is verlopen. Log opnieuw in.")
            throw APIError(code: "unauthorized", status: 401)
        }
        do {
            return try await api.send(action, token: token, params: params, as: type, timeout: timeout)
        } catch let e as APIError where e.isUnauthorized {
            logout("Je sessie is verlopen. Log opnieuw in.")
            throw e
        }
    }

    func call(_ action: String, _ params: [String: Any] = [:]) async throws {
        _ = try await call(action, params, as: OKResponse.self)
    }

    /// Aantallen per status in de inbox van één postvak (de server telt over alle postvakken, dus tellen we hier de eigen tickets).
    func mailCounts(for brand: MailBrand) async -> MailCounts? {
        guard isSignedIn, !isLocked else { return nil }
        let params: [String: Any] = ["box": "inbox", "status": "all", "q": "", "page": 0, "page_size": 100, "brand": brand.rawValue]
        guard let r = try? await call("mail_thread_list", params, as: MailThreadList.self) else { return nil }
        var n = 0, o = 0, p = 0, c = 0, u = 0
        for t in r.items {
            switch t.status {
            case "new": n += 1
            case "open": o += 1
            case "pending": p += 1
            default: c += 1
            }
            if t.unread == true && t.status != "closed" { u += 1 }
        }
        return MailCounts(new: n, open: o, pending: p, closed: c, unread: u)
    }

    /// Ongelezen mails voor de badges van de twee postvakken (stil negeren als de server het nog niet kent).
    func refreshMailBadge() async {
        guard isSignedIn, !isLocked else { return }
        if let c = await mailCounts(for: .pasr) { mailUnread = c.unread ?? 0 }
        if let c = await mailCounts(for: .zakelijk) { mailUnreadOwners = c.unread ?? 0 }
    }

    func requestRefresh() {
        guard isSignedIn, !isLocked else { return }
        refreshTick &+= 1
    }

    /// pasrbeheer://overview, ://accounts, ://stores, ://settings, ://mail (Postvak Support) of ://ownersMail (uit een pushmelding).
    func open(_ url: URL) {
        guard url.scheme?.lowercased() == "pasrbeheer" else { return }
        let host = url.host ?? ""
        if host == "mail" { section = .supportMail } else if let s = AppSection(rawValue: host) { section = s }
        requestRefresh()
    }

    // MARK: vergrendelen

    var canLock: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:
            #if os(macOS)
            return "je wachtwoord"
            #else
            return "je toegangscode"
            #endif
        }
    }

    var biometryIcon: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.open"
        }
    }

    func unlock() async {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Annuleren"
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { isLocked = false; return }
        if (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Ontgrendel PasrBeheer")) == true {
            isLocked = false
            requestRefresh()
        }
    }

    /// Uitzetten alleen na bevestigen met Face ID / Touch ID / code.
    func setLockEnabled(_ on: Bool) async {
        guard !on else { lockEnabled = true; return }
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { lockEnabled = false; return }
        let ok = (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Vergrendeling uitzetten")) == true
        lockEnabled = !ok
    }

    func didLeaveForeground() {
        if backgroundSince == nil { backgroundSince = .now }
    }

    func didEnterForeground() {
        defer { backgroundSince = nil }
        guard let since = backgroundSince, lockEnabled, isSignedIn, !isLocked, canLock else { return }
        if Date.now.timeIntervalSince(since) >= Self.lockAfter {
            isLocked = true
            autoUnlockTried = false
        }
    }
}
