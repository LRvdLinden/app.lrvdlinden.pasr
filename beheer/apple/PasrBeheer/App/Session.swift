import Foundation
import LocalAuthentication
import SwiftUI

/// Onderdelen (tabs op de iPhone, zijbalk op iPad en Mac).
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview, insights, accounts, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overzicht"
        case .insights: "Insights"
        case .accounts: "Accounts"
        case .settings: "Instellingen"
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .insights: "chart.xyaxis.line"
        case .accounts: "person.2"
        case .settings: "gearshape"
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
    }

    func logoutAll() async throws {
        try await api.raw("logout_all", token: token)
        PushService.shared.forget()
        logout("Je bent overal uitgelogd.")
    }

    /// Actie met het token; bij 401 terug naar inloggen.
    func call<T: Decodable>(_ action: String, _ params: [String: Any] = [:], as type: T.Type) async throws -> T {
        if let exp = expiresAt, exp <= .now {
            logout("Je sessie is verlopen. Log opnieuw in.")
            throw APIError(code: "unauthorized", status: 401)
        }
        do {
            return try await api.send(action, token: token, params: params, as: type)
        } catch let e as APIError where e.isUnauthorized {
            logout("Je sessie is verlopen. Log opnieuw in.")
            throw e
        }
    }

    func call(_ action: String, _ params: [String: Any] = [:]) async throws {
        _ = try await call(action, params, as: OKResponse.self)
    }

    func requestRefresh() {
        guard isSignedIn, !isLocked else { return }
        refreshTick &+= 1
    }

    /// pasrbeheer://overview, ://accounts, ://settings (uit een pushmelding).
    func open(_ url: URL) {
        guard url.scheme?.lowercased() == "pasrbeheer" else { return }
        if let s = AppSection(rawValue: url.host ?? "") { section = s }
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
