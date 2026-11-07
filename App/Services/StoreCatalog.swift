import Foundation
import Observation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Haalt winkels op die in het beheer zijn toegevoegd (zonder app-update) en bewaart ze met logo. Bij openen van de app
/// en als hij terugkomt, hoogstens elk kwartier; alleen wat sinds de vorige keer veranderde komt mee.
@MainActor
@Observable
final class StoreCatalog {
    static let shared = StoreCatalog()
    /// Telt op bij elke wijziging, zodat lijsten opnieuw tekenen.
    private(set) var version = 0
    private var lastCheck: Date?
    private let sinceKey = "pasr.storecatalog.since"

    func refresh(force: Bool = false) async {
        guard AccountConfig.isConfigured else { return }
        if !force, let lastCheck, Date.now.timeIntervalSince(lastCheck) < 900 { return }
        lastCheck = .now
        var body: [String: Any] = [:]
        body["p_since"] = UserDefaults.standard.string(forKey: sinceKey) ?? NSNull()
        guard let json = try? await AccountService.shared.publicRPC("pasr_store_catalog", body: body) as? [String: Any] else { return }
        if let pages = json["balance_pages"] as? [String: String] { BalancePages.save(pages) }
        let rows = json["stores"] as? [[String: Any]] ?? []
        if !rows.isEmpty {
            var list = Dictionary(RemoteStores.load().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for row in rows {
                guard let id = row["id"] as? String else { continue }
                if row["removed"] as? Bool == true { list[id] = nil; continue }
                let store = RemoteStores.Stored(
                    id: id, name: row["name"] as? String ?? id, domain: row["domain"] as? String ?? "",
                    category: row["category"] as? String ?? "Overig", cardHex: row["card_hex"] as? String ?? "#2B2F3A",
                    format: row["format"] as? String ?? "code128", kind: row["kind"] as? String ?? "loyalty",
                    aliases: row["aliases"] as? [String] ?? [])
                list[id] = store
                if let logo = (row["logo"] as? String).flatMap({ Data(base64Encoded: $0) }), let url = RemoteStores.logoURL(for: store.domain) {
                    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? logo.write(to: url, options: .atomic)
                }
            }
            RemoteStores.save(Array(list.values).sorted { $0.name < $1.name })
            version += 1
        }
        if let now = json["now"] as? String { UserDefaults.standard.set(now, forKey: sinceKey) }
    }
}

/// Pushmeldingen voor gebruikers: alleen "je aangevraagde winkel is toegevoegd" en (als je dat wilt) "nieuwe winkel".
/// Het apparaat meldt zich aan bij je Pasr-account; zonder account geen pushmeldingen.
@MainActor
enum UserPush {
    static let newStoresKey = "pasr.push.newStores"
    private static let tokenKey = "pasr.push.token"
    private static let deviceKey = "pasr.push.device"

    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: deviceKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceKey)
        return id
    }

    /// Vraagt toestemming (eenmalig) en meldt het apparaat aan bij Apple.
    @discardableResult
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
        return true
    }

    /// Bij het starten: als er al toestemming is, opnieuw aanmelden (tokens kunnen veranderen).
    static func refreshIfAllowed() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    static func didRegister(token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        Task { await sync() }
    }

    private static var syncedFor: String?

    /// Eén keer per account per keer dat de app draait (na inloggen of synchroniseren).
    static func syncOnce() async {
        guard let user = AccountService.shared.session?.userID, syncedFor != user else { return }
        syncedFor = user
        await sync()
    }

    /// Token en voorkeur naar het account (na inloggen en bij wijzigen van de schakelaar).
    static func sync() async {
        guard AccountService.shared.isSignedIn, let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        _ = try? await AccountService.shared.rpc("pasr_push_register", body: [
            "p_device": deviceID, "p_token": token, "p_sandbox": sandbox,
            "p_new_stores": UserDefaults.standard.bool(forKey: newStoresKey),
        ])
    }
}

#if canImport(UIKit)
/// Ontvangt het APNs-token van iOS.
final class PasrAppDelegate: NSObject, UIApplicationDelegate {
    /// Ook bij een start op de achtergrond na een verplaatsing (locatie): weer meeluisteren en opnieuw plannen.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { NearbyStores.shared.resume() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in UserPush.didRegister(token: deviceToken) }
    }
}
#endif
