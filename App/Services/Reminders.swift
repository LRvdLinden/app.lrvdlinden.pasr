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

/// Opens the card from a tapped notification.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    /// Set when a notification is tapped; RootView opens that card.
    @MainActor static var pendingCardID: UUID? {
        didSet { NotificationCenter.default.post(name: .pasrOpenCard, object: nil) }
    }
    /// Pushmelding "nieuwe winkel": RootView opent Kaart toevoegen bij die winkel.
    @MainActor static var pendingStoreID: String? {
        didSet { NotificationCenter.default.post(name: .pasrOpenStore, object: nil) }
    }

    func activate() { UNUserNotificationCenter.current().delegate = self }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if let id = (info["cardID"] as? String).flatMap(UUID.init) {
            await MainActor.run { Self.pendingCardID = id }
        } else if info["kind"] as? String == "store", let store = info["store"] as? String {
            await MainActor.run { Self.pendingStoreID = store }
        }
    }

    /// Also show them while Pasr is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

extension Notification.Name {
    static let pasrOpenCard = Notification.Name("pasrOpenCard")
    static let pasrOpenStore = Notification.Name("pasrOpenStore")
}


/// Plant de plekken voor "Kaart tonen bij de winkel" als Pasr naar voren komt, en opnieuw als eigen locaties
/// veranderen. Met de toestemming Altijd doet iOS het daarna zelf bij een verplaatsing (zie NearbyStores).
struct RemindersModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]

    private var placesFingerprint: String {
        cards.map { "\($0.id)\($0.placesData?.count ?? 0)\($0.storeName)" }.sorted().joined()
    }

    func body(content: Content) -> some View {
        content
            .task { await NearbyStores.shared.refresh(cards: cards) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await NearbyStores.shared.refresh(cards: cards) } }
            }
            .onChange(of: placesFingerprint) { _, _ in
                Task { await NearbyStores.shared.sourcesChanged(cards: cards) }
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
    @AppStorage(UserPush.newStoresKey) private var newStores = false
    @State private var note: String?
    private var stores: NearbyStores { .shared }

    var body: some View {
        Section {
            Toggle(isOn: $vouchers) {
                SettingsLabel("Herinnering als een voucher verloopt", symbol: "bell.badge.fill", color: .red)
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
                SettingsLabel("Kaart tonen bij de winkel", symbol: "location.fill", color: .blue)
            }

            if nearby {
                if stores.hasAlways {
                    LabeledContent {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.mint)
                    } label: {
                        SettingsLabel("Ook als Pasr dicht is", symbol: "location.circle.fill", color: .blue)
                    }
                } else {
                    Button { stores.requestAlways() } label: {
                        HStack {
                            SettingsLabel("Ook als Pasr dicht is", symbol: "location.circle", color: .blue)
                            Spacer()
                            Text("Zet aan").foregroundStyle(Brand.iris)
                        }
                    }
                    .tint(.primary)
                }
                NavigationLink {
                    NearbyPlacesView()
                } label: {
                    LabeledContent {
                        Text("\(stores.placesWatched)")
                    } label: {
                        SettingsLabel("Winkels in de buurt", symbol: "mappin.and.ellipse", color: Brand.coral)
                    }
                }
            }

            if AccountService.shared.isSignedIn {
                Toggle(isOn: Binding(get: { newStores }, set: { on in
                    newStores = on
                    Task {
                        if on, !(await UserPush.enable()) {
                            newStores = false
                            note = String(localized: "Sta meldingen voor Pasr toe in de Instellingen van je iPhone.")
                        }
                        await UserPush.sync()
                    }
                })) {
                    SettingsLabel("Nieuwe winkels in Pasr", symbol: "storefront.fill", color: Brand.mint)
                }
            }
        } header: {
            Text("Meldingen")
        } footer: {
            Text(note ?? footer)
        }
    }

    private var footer: String {
        guard nearby else {
            return String(localized: "Bij de winkel verschijnt je kaart met een melding. Je locatie blijft op je iPhone.")
        }
        if stores.hasAlways {
            return String(localized: "Pasr zet de winkels om je heen vanzelf klaar als je ergens anders bent, ook als je de app niet opent. Je locatie blijft op je iPhone.")
        }
        return String(localized: "Pasr zet de winkels om je heen klaar als je de app opent. Met \u{201C}Ook als Pasr dicht is\u{201D} gebeurt dat ook als je ergens anders bent zonder Pasr te openen. Je locatie blijft op je iPhone.")
    }
}

/// Instellingen › Winkels in de buurt: welke plekken iOS nu bewaakt (hoogstens 20), eigen locaties eerst.
struct NearbyPlacesView: View {
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    private var stores: NearbyStores { .shared }
    @State private var busy = false

    var body: some View {
        List {
            Section {
                if stores.watched.isEmpty {
                    Text("Nog geen winkels gevonden. Trek omlaag of tik op Zoek opnieuw.").foregroundStyle(.secondary)
                }
                ForEach(stores.watched) { place in
                    HStack(spacing: 12) {
                        Image(systemName: place.own ? "mappin.circle.fill" : "storefront.circle.fill")
                            .font(.title2)
                            .foregroundStyle(place.own ? Brand.coral : Brand.iris)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.store).font(.body.weight(.semibold))
                            Text(place.own ? String(localized: "Eigen locatie") + (place.name == place.store ? "" : " · \(place.name)") : place.name)
                                .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let here = stores.lastLocation {
                            Text(Self.distance(here.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))))
                                .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("iOS laat een app hoogstens 20 plekken tegelijk bewaken. Eigen locaties gaan voor; voeg ze toe bij een kaart onder Wijzig › Locaties.")
            }
            if let plan = stores.lastPlan {
                Section {
                    LabeledContent("Bijgewerkt", value: plan.formatted(.relative(presentation: .named)))
                }
            }
        }
        .navigationTitle("Winkels in de buurt")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if busy { ProgressView() } else {
                    Button("Zoek opnieuw", systemImage: "arrow.clockwise") { Task { await reload() } }
                }
            }
        }
        .refreshable { await reload() }
    }

    private func reload() async {
        busy = true
        defer { busy = false }
        await stores.refresh(cards: cards, force: true)
    }

    static func distance(_ meters: CLLocationDistance) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }
}
