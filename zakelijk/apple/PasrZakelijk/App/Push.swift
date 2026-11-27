import SwiftUI
import UserNotifications
import Observation
#if os(iOS)
import UIKit
import SafariServices
#else
import AppKit
#endif

/// Pushmeldingen van Pasr Zakelijk (iOS). De app vraagt één keer toestemming, op een rustig moment nadat je zaak is
/// goedgekeurd, en meldt het APNs-token met `pasr_device_register` (app zakelijk, platform ios). Zo bereikt een belangrijk
/// bericht uit het beheer ("Iedereen met meldingen aan") ook ondernemers. Een tik op een melding met `url` opent die link:
/// een uitnodigingslink van pasr.nl op de juiste plek in de app, andere https-links in Safari in de app.
@MainActor
enum ZakelijkPush {
    private static let tokenKey = "push.apnsToken"
    private static let askedKey = "push.asked"

    static var token: String? { UserDefaults.standard.string(forKey: tokenKey) }

    /// Eén keer vragen. Staat het al aan (of uit), dan niet opnieuw vragen; wel het token vernieuwen als het mag.
    static func askOnce() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus != .notDetermined || UserDefaults.standard.bool(forKey: askedKey) {
            await refreshIfAllowed()
            return
        }
        UserDefaults.standard.set(true, forKey: askedKey)
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { registerRemote() }
    }

    /// Bij het starten: met toestemming opnieuw aanmelden bij Apple (tokens kunnen veranderen).
    static func refreshIfAllowed() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        registerRemote()
    }

    /// Aanmelden bij APNs (iOS en macOS; zelfde bundle-id, dus hetzelfde APNs-topic).
    private static func registerRemote() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #else
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    static func didRegister(token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
        Task { await DeviceRegistry.registerIfNeeded() }
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

/// Meldt hoogstens één keer per dag (en na inloggen, een update of een nieuw pushtoken) welke app, welk platform en
/// welke versie dit toestel draait: `pasr_device_register` (p_app zakelijk, p_platform ios), met het APNs-token als
/// meldingen aanstaan. Alleen een willekeurige id per installatie.
@MainActor
enum DeviceRegistry {
    private static let idKey = "device.registryID"
    private static let atKey = "device.registeredAt"
    private static let stampKey = "device.registeredStamp"

    private static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: idKey) { return id }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(id, forKey: idKey)
        return id
    }

    static func registerIfNeeded(force: Bool = false) async {
        guard let user = Account.shared.session?.userID else { return }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? ""
        let token = ZakelijkPush.token
        let stamp = "\(version)|\(build)|\(user)|\(token?.suffix(12) ?? "-")"
        let last = UserDefaults.standard.double(forKey: atKey)
        if !force, Date.now.timeIntervalSince1970 - last < 86_400, UserDefaults.standard.string(forKey: stampKey) == stamp { return }
        var body: [String: Any] = ["p_device": deviceID, "p_app": "zakelijk", "p_platform": "ios", "p_version": version,
                                   "p_build": build, "p_os": DeviceInfo.osLine]
        if let region = Locale.current.region?.identifier, region.count == 2 { body["p_country"] = region }
        var ok = false
        if let token {
            var withPush = body
            withPush["p_push_token"] = token
            withPush["p_push_provider"] = "apns"
            withPush["p_push_sandbox"] = PushEnvironment.isSandbox
            ok = (try? await Account.shared.rpc("pasr_device_register", withPush)) != nil
        }
        // zonder token, of een server die het token nog niet kent: alleen app, platform en versie (morgen opnieuw)
        if !ok { ok = (try? await Account.shared.rpc("pasr_device_register", body)) != nil }
        if ok {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: atKey)
            UserDefaults.standard.set(stamp, forKey: stampKey)
        }
    }
}

/// Link uit een getikte melding; AppShell opent hem zodra splash en Face ID-slot weg zijn.
@MainActor
@Observable
final class NotificationLink {
    static let shared = NotificationLink()
    var pending: URL?
}

#if os(iOS)
/// Appdelegate: APNs-token ontvangen en tikken op meldingen afhandelen.
final class ZakelijkAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in ZakelijkPush.didRegister(token: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    /// Ook tonen terwijl de app open is.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // nieuwe uitnodiging of antwoord voor een gezamenlijke actie: badge meteen bijwerken
        if let type = notification.request.content.userInfo["type"] as? String, CommunityRouter.pushTypes.contains(type) {
            Task { @MainActor in
                if let business = BusinessStore.shared.current { await CommunityRouter.shared.refreshCount(business: business) }
            }
        }
        completionHandler([.banner, .list, .sound])
    }

    // Met een completion handler (niet async): dan roept iOS de afhandeling op de hoofdthread aan.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        ZakelijkNotificationRouter.open(response.notification.request.content.userInfo)
        completionHandler()
    }
}
#endif

/// Tik op een melding (iOS en Mac): gezamenlijke acties naar Samenwerkingen, een widget-/app-link naar het juiste scherm,
/// andere https-links in de browser.
enum ZakelijkNotificationRouter {
    static func open(_ info: [AnyHashable: Any]) {
        let link = (info["url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
        // gezamenlijke acties: type community_invite | community_invite_answered | community_active | community_removed
        let type = info["type"] as? String
        let campaign = (info["campaign"] as? String) ?? (info["campaign"] as? NSNumber)?.stringValue
        let businessID = info["business_id"] as? String
        let appLink = (info["app_url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "pasrzakelijk" ? $0 : nil }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let type, CommunityRouter.pushTypes.contains(type) {
                    if let businessID, !businessID.isEmpty { BusinessStore.shared.select(businessID) }
                    CommunityRouter.shared.route(type: type, campaign: campaign)
                } else if let app = appLink {
                    BusinessStore.shared.handle(url: app)
                } else if let link {
                    NotificationLink.shared.pending = link
                }
            }
        }
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

#if os(iOS)
/// Safari in de app (SFSafariViewController) voor links uit meldingen.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Theme.accent)
        vc.dismissButtonStyle = .done
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
#endif
