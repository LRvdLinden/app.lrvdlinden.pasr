import Foundation
import UserNotifications

/// Lokale meldingen op de Mac zolang er geen APNs-token is (push nog niet aangezet voor de Mac of geen toestemming):
/// na verversen een melding bij een nieuwe uitnodiging voor een gezamenlijke actie. Met een APNs-token stuurt de server
/// de melding zelf (zoals op iOS) en doet dit niets.
@MainActor
enum LocalNotices {
    private static let seenKey = "notices.seenInvites"

    static func check(_ businesses: [WidgetSnapshot.Business]) async {
        #if os(macOS)
        guard ZakelijkPush.token == nil else { return }
        let invites = businesses.flatMap { b in b.todo.filter { $0.kind == .invite }.map { (b, $0) } }
        let defaults = UserDefaults.standard
        let firstRun = defaults.object(forKey: seenKey) == nil
        var seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        let fresh = invites.filter { !seen.contains($0.1.id) }
        seen.formUnion(invites.map(\.1.id))
        defaults.set(Array(seen.suffix(200)), forKey: seenKey)
        // de eerste keer alleen onthouden wat er al was (geen stapel meldingen na installeren)
        guard !firstRun, !fresh.isEmpty else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for (business, item) in fresh.prefix(3) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Uitnodiging voor een gezamenlijke actie")
            content.body = "\(item.title) · \(business.name)"
            content.sound = .default
            content.userInfo = ["app_url": ZakelijkLink.url(.gezamenlijkeActies, business: business.id, item: item.item).absoluteString]
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
        #endif
    }
}
