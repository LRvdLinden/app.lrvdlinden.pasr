import Foundation
import UserNotifications
import CoreLocation
import MapKit
import Observation
import SwiftUI
import SwiftData

/// Local notifications, planned by the iPhone itself (no server):
/// - vouchers: a reminder a week before and on the day they expire;
/// - "at the store": when you arrive at a branch of a store you have a card for, a notification that opens
///   that card straight away (like Apple Wallet does on the lock screen).
enum Reminders {
    static let voucherKey = "pasr.reminders.vouchers"
    static let nearbyKey = "pasr.reminders.nearby"

    static var vouchersEnabled: Bool { UserDefaults.standard.object(forKey: voucherKey) as? Bool ?? true }
    static var nearbyEnabled: Bool { UserDefaults.standard.bool(forKey: nearbyKey) }

    /// Asks for permission to show notifications (once; iOS remembers the answer).
    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: Vouchers

    /// Plans the reminders for all vouchers with an expiry date again (cheap; runs whenever cards change).
    @MainActor
    static func rescheduleVouchers(_ cards: [Card]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("voucher-") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard vouchersEnabled else { return }
        let vouchers = cards.filter { $0.deletedAt == nil && $0.kind == .voucher && $0.expiresAt != nil }
        guard !vouchers.isEmpty else { return }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined { await requestPermission() }

        let calendar = Calendar.current
        for card in vouchers {
            guard let expires = card.expiresAt else { continue }
            let day = calendar.startOfDay(for: expires)
            let balance = CardAppearance(card).balanceText
            let moments: [(Int, String, String)] = [
                (-7, String(localized: "\(card.storeName) verloopt over een week"),
                 balance.map { String(localized: "Je hebt nog \($0) tegoed. Gebruik je kaart op tijd.") }
                    ?? String(localized: "Gebruik je kaart op tijd.")),
                (0, String(localized: "\(card.storeName) verloopt vandaag"),
                 balance.map { String(localized: "Laatste dag om je \($0) te gebruiken.") }
                    ?? String(localized: "Laatste dag om je kaart te gebruiken.")),
            ]
            for (offset, title, body) in moments {
                guard let date = calendar.date(byAdding: .day, value: offset, to: day),
                      let fire = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: date), fire > .now else { continue }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.userInfo = ["cardID": card.id.uuidString]
                content.threadIdentifier = "vouchers"
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "voucher-\(card.id.uuidString)-\(offset)",
                                                            content: content, trigger: trigger))
            }
        }
    }
}

/// Finds the branches of your stores around you (Apple Maps, on the device) and lets iOS show a notification
/// when you walk in. iOS allows 20 places per app, so the nearest 20 are used and refreshed when you open Pasr.
@MainActor
@Observable
final class NearbyStores: NSObject, CLLocationManagerDelegate {
    static let shared = NearbyStores()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private(set) var lastRefresh: Date?
    private(set) var placesWatched = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    /// Switches the feature on: asks for location and notifications, then plans the places.
    func enable(cards: [Card]) async -> Bool {
        UserDefaults.standard.set(true, forKey: Reminders.nearbyKey)
        guard await Reminders.requestPermission() else { return false }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        await refresh(cards: cards, force: true)
        return manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    func disable() async {
        UserDefaults.standard.set(false, forKey: Reminders.nearbyKey)
        await removeAll()
    }

    private func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("nearby-") }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        placesWatched = 0
    }

    /// Looks up the nearest branches again (at most once an hour unless forced).
    func refresh(cards: [Card], force: Bool = false) async {
        guard Reminders.nearbyEnabled else { return }
        if !force, let last = lastRefresh, Date.now.timeIntervalSince(last) < 3600 { return }
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways,
              let here = await currentLocation() else { return }
        lastRefresh = .now

        // One entry per store you have a card for (the card that opens when you arrive).
        var stores: [(name: String, cardID: UUID)] = []
        var seen = Set<String>()
        for card in cards.alphabetical() where card.deletedAt == nil {
            let name = StoreTemplates.template(id: card.templateID)?.name ?? card.storeName
            let key = name.lowercased()
            guard !name.isEmpty, !name.contains("eigen kaart"), seen.insert(key).inserted else { continue }
            stores.append((name, card.id))
        }

        var places: [(distance: CLLocationDistance, store: String, cardID: UUID, coordinate: CLLocationCoordinate2D)] = []
        for store in stores.prefix(40) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = store.name
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 15_000, longitudinalMeters: 15_000)
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }
            let wanted = Self.squash(store.name)
            for item in response.mapItems.prefix(10) {
                // Only real branches of that store (Maps also returns things that merely mention the name).
                guard let name = item.name, Self.squash(name).contains(wanted) || wanted.contains(Self.squash(name)) else { continue }
                let coordinate = item.placemark.coordinate
                let distance = here.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                places.append((distance, store.name, store.cardID, coordinate))
            }
        }
        // Nearest 20, at most 3 per store so one chain doesn't take every place.
        var perStore: [String: Int] = [:]
        let chosen = places.sorted { $0.distance < $1.distance }.filter { place in
            perStore[place.store, default: 0] += 1
            return perStore[place.store]! <= 3
        }.prefix(20)

        await removeAll()
        let center = UNUserNotificationCenter.current()
        for (index, place) in chosen.enumerated() {
            let region = CLCircularRegion(center: place.coordinate, radius: 120, identifier: "nearby-\(index)")
            region.notifyOnEntry = true
            region.notifyOnExit = false
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Je bent bij \(place.store)")
            content.body = String(localized: "Tik om je kaart te tonen.")
            content.userInfo = ["cardID": place.cardID.uuidString]
            content.threadIdentifier = "nearby"
            content.interruptionLevel = .active
            content.relevanceScore = 1
            let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "nearby-\(index)", content: content, trigger: trigger))
        }
        placesWatched = chosen.count
    }

    /// "AH" and "Albert Heijn", "Kruidvat Apeldoorn" → lowercase letters and digits only.
    private static func squash(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func currentLocation() async -> CLLocation? {
        if let recent = manager.location, Date.now.timeIntervalSince(recent.timestamp) < 600 { return recent }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            self.continuation?.resume(returning: location)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(returning: nil)
            self.continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}

/// Opens the card from a tapped notification.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    /// Set when a notification is tapped; RootView opens that card.
    @MainActor static var pendingCardID: UUID? {
        didSet { NotificationCenter.default.post(name: .pasrOpenCard, object: nil) }
    }

    func activate() { UNUserNotificationCenter.current().delegate = self }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let id = (response.notification.request.content.userInfo["cardID"] as? String).flatMap(UUID.init) {
            await MainActor.run { Self.pendingCardID = id }
        }
    }

    /// Also show them while Pasr is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

extension Notification.Name {
    static let pasrOpenCard = Notification.Name("pasrOpenCard")
}


/// Refreshes the "at the store" places when Pasr comes to the front (iOS keeps watching them afterwards).
struct RemindersModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]

    func body(content: Content) -> some View {
        content
            .task { await NearbyStores.shared.refresh(cards: cards) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await NearbyStores.shared.refresh(cards: cards) } }
            }
    }
}

extension View {
    func reminders() -> some View { modifier(RemindersModifier()) }
}

/// Settings: voucher reminders and the card at the store.
struct RemindersSettingsSection: View {
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @AppStorage(Reminders.voucherKey) private var vouchers = true
    @AppStorage(Reminders.nearbyKey) private var nearby = false
    @State private var note: String?
    private var stores: NearbyStores { .shared }

    var body: some View {
        Section {
            Toggle(isOn: $vouchers) {
                Label("Herinnering als een voucher verloopt", systemImage: "bell.badge")
            }
            .onChange(of: vouchers) { _, _ in Task { await Reminders.rescheduleVouchers(cards) } }

            Toggle(isOn: Binding(get: { nearby }, set: { on in
                Task {
                    if on {
                        let ok = await stores.enable(cards: cards)
                        note = ok ? nil : String(localized: "Geef Pasr toegang tot je locatie en meldingen in de Instellingen van je iPhone.")
                    } else {
                        await stores.disable()
                        note = nil
                    }
                }
            })) {
                Label("Kaart tonen bij de winkel", systemImage: "location.fill")
            }
        } header: {
            Text("Meldingen")
        } footer: {
            Text(note ?? footer)
        }
    }

    private var footer: String {
        var text = String(localized: "Een week voor en op de dag dat een cadeaukaart of voucher verloopt, krijg je een seintje.")
        text += " "
        text += String(localized: "Met \"Kaart tonen bij de winkel\" verschijnt je kaart op je toegangsscherm zodra je een winkel binnenloopt; tik erop en de kaart staat klaar. Pasr zoekt de dichtstbijzijnde filialen op je iPhone zelf; je locatie gaat nergens heen.")
        if nearby, stores.placesWatched > 0 {
            text += " " + String(localized: "Nu actief voor \(stores.placesWatched) winkels in de buurt.")
        }
        return text
    }
}
