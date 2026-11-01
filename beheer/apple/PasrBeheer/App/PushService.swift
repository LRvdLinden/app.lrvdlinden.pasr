import Foundation
import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Welke meldingen dit apparaat wil (prefs in admin_push_devices).
struct PushPrefs: Codable, Equatable {
    var signups = true
    var confirmed = false
    var deleted = true
    var bots = true

    var params: [String: Bool] { ["signups": signups, "confirmed": confirmed, "deleted": deleted, "bots": bots] }
}

/// Pushmeldingen van PasrBeheer (APNs, topic nl.lrvdlinden.pasr.beheer) op iPhone, iPad en Mac.
/// Het APNs-token gaat met `push_register` naar de functie admin; uitloggen meldt het apparaat af.
@MainActor
@Observable
final class PushService {
    static let shared = PushService()

    enum Permission: Equatable { case unknown, notDetermined, denied, allowed }

    private(set) var permission: Permission = .unknown
    private(set) var registered = false
    private(set) var lastError: String?
    /// Uitleg vóór de systeemvraag (eenmalig na het inloggen).
    var showPrompt = false
    private(set) var prefs: PushPrefs

    @ObservationIgnored private weak var session: Session?
    @ObservationIgnored private var pendingURL: URL?
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var resync = false
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum K {
        static let deviceID = "push.device_id"
        static let token = "push.token"
        static let prefs = "push.prefs"
        static let registration = "push.registration"
        static let sentPrefs = "push.sent_prefs"
        static let prompted = "push.prompted"
    }

    private init() {
        prefs = UserDefaults.standard.data(forKey: K.prefs).flatMap { try? JSONDecoder().decode(PushPrefs.self, from: $0) } ?? PushPrefs()
        registered = UserDefaults.standard.string(forKey: K.registration) != nil
    }

    var deviceID: String {
        if let id = defaults.string(forKey: K.deviceID), id.count >= 8 { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: K.deviceID)
        return id
    }

    private var apnsToken: String? {
        get { defaults.string(forKey: K.token) }
        set { defaults.set(newValue, forKey: K.token) }
    }

    static var platform: String {
        #if os(macOS)
        return "macos"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios"
        #endif
    }

    static var appBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }

    /// Sandbox voor debug-builds en ontwikkelprofielen; productie voor TestFlight en App Store.
    static let sandbox: Bool = {
        #if DEBUG
        return true
        #else
        return ProvisioningProfile.apsEnvironment == "development"
        #endif
    }()

    // MARK: starten

    func attach(_ session: Session) {
        self.session = session
        if let url = pendingURL {
            pendingURL = nil
            session.open(url)
        }
        Task { await refresh() }
    }

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: permission = .notDetermined
        case .denied: permission = .denied
        default: permission = .allowed
        }
        guard session?.isSignedIn == true else { return }
        if permission == .allowed {
            #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
            #else
            NSApplication.shared.registerForRemoteNotifications()
            #endif
            sync()
        } else if permission == .denied && registered {
            await unregister()
        }
    }

    func didSignIn() {
        defaults.removeObject(forKey: K.registration)
        registered = false
        Task {
            await refresh()
            try? await Task.sleep(for: .seconds(3))
            guard session?.isSignedIn == true, session?.isLocked == false, permission == .notDetermined,
                  !defaults.bool(forKey: K.prompted) else { return }
            showPrompt = true
        }
    }

    func answerPrompt(_ yes: Bool) {
        defaults.set(true, forKey: K.prompted)
        showPrompt = false
        if yes { Task { await requestPermission() } }
    }

    func requestPermission() async {
        defaults.set(true, forKey: K.prompted)
        if permission == .denied { openSystemSettings(); return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }

    func openSystemSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        #endif
    }

    // MARK: APNs

    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        if hex != apnsToken {
            apnsToken = hex
            defaults.removeObject(forKey: K.registration)
            registered = false
        }
        sync()
    }

    func didFailToRegister() {
        lastError = "Apple gaf geen pushtoken. Staat Push Notifications aan voor deze app-id?"
    }

    // MARK: server

    private var signature: String? {
        guard let t = apnsToken else { return nil }
        return [t, Self.platform, String(Self.appBuild), Self.sandbox ? "sandbox" : "production"].joined(separator: "|")
    }

    func sync() {
        guard !syncing else { resync = true; return }
        syncing = true
        Task {
            repeat {
                resync = false
                await performSync()
            } while resync
            syncing = false
        }
    }

    private func performSync() async {
        guard let session, session.isSignedIn, permission == .allowed, let token = apnsToken, let sig = signature else { return }
        let sent = defaults.data(forKey: K.sentPrefs).flatMap { try? JSONDecoder().decode(PushPrefs.self, from: $0) }
        if defaults.string(forKey: K.registration) == sig {
            guard sent != prefs else { return }
            do {
                try await session.call("push_prefs", ["device_id": deviceID, "prefs": prefs.params])
                rememberPrefs()
                return
            } catch let e as APIError where e.code == "not_registered" {
                defaults.removeObject(forKey: K.registration)
            } catch { return }
        }
        do {
            try await session.call("push_register", [
                "device_id": deviceID, "apns_token": token, "platform": Self.platform, "sandbox": Self.sandbox,
                "app_build": Self.appBuild, "prefs": prefs.params,
            ])
            defaults.set(sig, forKey: K.registration)
            rememberPrefs()
            registered = true
            lastError = nil
        } catch let e as APIError {
            if !e.isUnauthorized { lastError = e.errorDescription }
        } catch {}
    }

    private func rememberPrefs() {
        if let data = try? JSONEncoder().encode(prefs) { defaults.set(data, forKey: K.sentPrefs) }
    }

    func setPref(_ change: (inout PushPrefs) -> Void) {
        var p = prefs
        change(&p)
        guard p != prefs else { return }
        prefs = p
        if let data = try? JSONEncoder().encode(p) { defaults.set(data, forKey: K.prefs) }
        sync()
    }

    func unregister() async {
        guard let session, session.isSignedIn else { forget(); return }
        if (try? await session.call("push_unregister", ["device_id": deviceID])) != nil { forget() }
    }

    /// Uitloggen: afmelden met het token van de sessie die eindigt.
    func signOut(token: String?) {
        let id = deviceID, was = registered
        forget()
        guard was, let token else { return }
        Task.detached { _ = try? await AdminAPI().raw("push_unregister", token: token, params: ["device_id": id]) }
    }

    func forget() {
        defaults.removeObject(forKey: K.registration)
        defaults.removeObject(forKey: K.sentPrefs)
        registered = false
        lastError = nil
        showPrompt = false
    }

    func sendTest() async throws {
        guard let session else { return }
        if !registered { await performSync() }
        try await session.call("push_test", ["device_id": deviceID])
    }

    func handleTap(_ raw: String?) {
        guard let raw, let url = URL(string: raw), url.scheme?.lowercased() == "pasrbeheer" else { return }
        if let session { session.open(url) } else { pendingURL = url }
    }
}

/// Meldingen ook tonen als de app open is, en een tik doorgeven.
final class PushNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let raw = response.notification.request.content.userInfo["url"] as? String
        await MainActor.run { PushService.shared.handleTap(raw) }
    }
}

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = PushNotificationDelegate.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushService.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushService.shared.didFailToRegister() }
    }
}
#else
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = PushNotificationDelegate.shared
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushService.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushService.shared.didFailToRegister() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif

/// `aps-environment` uit het ingebedde provisioning-profiel; nil zonder profiel (App Store).
enum ProvisioningProfile {
    static let apsEnvironment: String? = {
        #if os(macOS)
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile")
        let keys = ["com.apple.developer.aps-environment", "aps-environment"]
        #else
        let url = Bundle.main.bundleURL.appendingPathComponent("embedded.mobileprovision")
        let keys = ["aps-environment"]
        #endif
        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let dict = (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any],
              let ent = dict["Entitlements"] as? [String: Any] else { return nil }
        return keys.lazy.compactMap { ent[$0] as? String }.first
    }()
}
