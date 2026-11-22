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
    /// v2 (versie 1.0.2): één keer alles opnieuw ophalen, want sindsdien beheert het beheer ook de winkels in de app.
    /// v3 (build 40): nog één keer alles, voor de cadeaubon-gids (guide) per winkel.
    private let sinceKey = "pasr.storecatalog.since.v3"
    /// Of de server de gids al meestuurt. Zo niet, dan hoogstens één keer per dag alles opnieuw ophalen, zodat de gidsen
    /// er vanzelf komen zodra het beheer ze heeft.
    private let guideSeenKey = "pasr.storecatalog.guideSeen"
    private let fullFetchKey = "pasr.storecatalog.fullFetch"

    func refresh(force: Bool = false) async {
        guard AccountConfig.isConfigured else { return }
        if !force, let lastCheck, Date.now.timeIntervalSince(lastCheck) < 900 { return }
        lastCheck = .now
        let defaults = UserDefaults.standard
        var since = defaults.string(forKey: sinceKey)
        if since != nil, !defaults.bool(forKey: guideSeenKey),
           Date.now.timeIntervalSince1970 - defaults.double(forKey: fullFetchKey) > 86_400 {
            since = nil
        }
        var body: [String: Any] = [:]
        body["p_since"] = since ?? NSNull()
        guard let json = try? await AccountService.shared.publicRPC("pasr_store_catalog", body: body) as? [String: Any] else { return }
        if since == nil { defaults.set(Date.now.timeIntervalSince1970, forKey: fullFetchKey) }
        if let pages = json["balance_pages"] as? [String: String] { BalancePages.save(pages) }
        let rows = json["stores"] as? [[String: Any]] ?? []
        if rows.contains(where: { $0.keys.contains("guide") }) { defaults.set(true, forKey: guideSeenKey) }
        if !rows.isEmpty {
            var list = Dictionary(RemoteStores.load().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var removed = RemoteStores.removedIDs()
            for row in rows {
                guard let id = row["id"] as? String else { continue }
                if row["removed"] as? Bool == true {
                    if list[id]?.cover != nil { RemoteStores.saveCover(nil, for: id) }
                    list[id] = nil; removed.insert(id); continue
                }
                removed.remove(id)
                var store = RemoteStores.Stored(
                    id: id, name: row["name"] as? String ?? id, domain: row["domain"] as? String ?? "",
                    category: row["category"] as? String ?? "Overig", cardHex: row["card_hex"] as? String ?? "#2B2F3A",
                    format: row["format"] as? String ?? "code128", kind: row["kind"] as? String ?? "loyalty",
                    aliases: row["aliases"] as? [String] ?? [])
                // Kleur gewijzigd in het beheer: de oude onthouden, zodat kaarten in die kleur mee veranderen.
                var past = list[id]?.previousHex ?? []
                if let old = list[id]?.cardHex, old.caseInsensitiveCompare(store.cardHex) != .orderedSame { past.append(old) }
                store.previousHex = past.isEmpty ? nil : past
                store.guide = row.keys.contains("guide") ? StoreGuide(json: row["guide"]) : list[id]?.guide
                if let logo = (row["logo"] as? String).flatMap({ Data(base64Encoded: $0) }), let url = RemoteStores.logoURL(for: store.domain) {
                    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? logo.write(to: url, options: .atomic)
                }
                // Kaartontwerp: alleen meegestuurd als de winkel er een heeft; ontbreekt het, dan is het weg.
                if let cover = (row["cover"] as? String).flatMap({ Data(base64Encoded: $0) }) {
                    RemoteStores.saveCover(cover, for: id)
                    store.cover = row["updated_at"] as? String ?? "1"
                } else {
                    if list[id]?.cover != nil { RemoteStores.saveCover(nil, for: id) }
                }
                list[id] = store
            }
            RemoteStores.save(Array(list.values).sorted { $0.name < $1.name })
            RemoteStores.saveRemoved(removed)
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
        Task {
            await sync()
            // zonder account: "Nieuws over mijn kaarten" gaat via pasr_news_register (met account doet sync() het)
            if !(await AccountService.shared.isSignedIn) { await StorePush.syncIfEnabled(force: true) }
            // het token ook in het apparaatregister (bereikbaar voor "Iedereen met meldingen aan" uit het beheer)
            await DeviceRegistry.registerIfNeeded()
        }
    }

    private static var syncedFor: String?

    /// Heeft dit apparaat een APNs-token (meldingen toegestaan en aangemeld bij Apple)?
    static var hasToken: Bool { token != nil }
    static var token: String? { UserDefaults.standard.string(forKey: tokenKey) }

    /// Eén keer per account per keer dat de app draait (na inloggen of synchroniseren).
    static func syncOnce() async {
        guard let user = AccountService.shared.session?.userID, syncedFor != user else { return }
        syncedFor = user
        await sync()
    }

    /// Token en voorkeur naar het account (na inloggen en bij wijzigen van de schakelaar).
    static func sync() async {
        guard AccountService.shared.isSignedIn, let token = UserDefaults.standard.string(forKey: tokenKey) else { return }
        // Ontwikkelversie (Xcode) of productie (TestFlight/App Store): uit het ingebedde profiel, niet uit DEBUG,
        // want ook een Release-build vanuit Xcode krijgt een sandbox-token.
        let sandbox = PushEnvironment.isSandbox
        _ = try? await AccountService.shared.rpc("pasr_push_register", body: [
            "p_device": deviceID, "p_token": token, "p_sandbox": sandbox,
            "p_new_stores": UserDefaults.standard.bool(forKey: newStoresKey),
        ])
        // daarna (het apparaat staat nu op de server) de winkels voor "Nieuws over mijn kaarten"
        await StorePush.syncIfEnabled(force: true)
    }
}

/// `aps-environment` uit het ingebedde provisioning-profiel. Geen profiel (App Store, TestFlight) = productie.
enum PushEnvironment {
    static let isSandbox: Bool = {
        guard let data = try? Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let dict = (try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil)) as? [String: Any],
              let ent = dict["Entitlements"] as? [String: Any] else {
            #if DEBUG
            return true
            #else
            return false
            #endif
        }
        return (ent["aps-environment"] as? String) == "development"
    }()
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
