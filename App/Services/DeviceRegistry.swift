import Foundation
import UIKit

/// Meldt hoogstens één keer per dag (en na in-/uitloggen, een update of een nieuw pushtoken) welke app, welk platform en
/// welke versie dit toestel draait: `pasr_device_register` (contract android 1.0). Alleen een willekeurige id per
/// installatie; voor de inzichten iOS/Android in het beheer. Met meldingen aan gaat ook het APNs-token mee (provider
/// apns, sandbox of productie), zodat een belangrijk bericht uit het beheer ("Iedereen met meldingen aan") dit toestel
/// bereikt, ook zonder account en zonder "Nieuws over mijn kaarten".
@MainActor
enum DeviceRegistry {
    private static let idKey = "pasr.device.registryID"
    private static let atKey = "pasr.device.registeredAt"
    private static let stampKey = "pasr.device.registeredStamp"

    private static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: idKey) { return id }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(id, forKey: idKey)
        return id
    }

    static func registerIfNeeded(force: Bool = false) async {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? ""
        let token = UserPush.token
        let stamp = "\(version)|\(build)|\(AccountService.shared.session?.userID ?? "-")|\(token?.suffix(12) ?? "-")"
        let last = UserDefaults.standard.double(forKey: atKey)
        if !force, Date.now.timeIntervalSince1970 - last < 86_400, UserDefaults.standard.string(forKey: stampKey) == stamp { return }
        var body: [String: Any] = ["p_device": deviceID, "p_app": "pasr", "p_platform": "ios", "p_version": version,
                                   "p_build": build, "p_os": "iOS \(UIDevice.current.systemVersion)"]
        body["p_country"] = AccountService.deviceCountry ?? NSNull()
        var ok = false
        if let token {
            var withPush = body
            withPush["p_push_token"] = token
            withPush["p_push_provider"] = "apns"
            withPush["p_push_sandbox"] = PushEnvironment.isSandbox
            ok = (try? await AccountService.shared.publicRPC("pasr_device_register", body: withPush)) != nil
        }
        // zonder token, of een server die het token nog niet kent: alleen app, platform en versie (morgen opnieuw)
        if !ok { ok = (try? await AccountService.shared.publicRPC("pasr_device_register", body: body)) != nil }
        if ok {
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: atKey)
            UserDefaults.standard.set(stamp, forKey: stampKey)
        }
    }
}
