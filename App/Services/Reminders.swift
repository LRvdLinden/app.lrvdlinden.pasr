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
    /// Tegoed-herinnering (cadeaukaarten met tegoed, ook zonder vervaldatum) en hoe vaak.
    static let balanceKey = "pasr.reminders.balance"
    static let balanceIntervalKey = "pasr.reminders.balanceInterval"
    /// Hoe: "push", "mail" of "both". E-mail kan alleen met een Pasr-account.
    static let channelKey = "pasr.reminders.channel"

    static var vouchersEnabled: Bool { UserDefaults.standard.object(forKey: voucherKey) as? Bool ?? true }
    static var nearbyEnabled: Bool { UserDefaults.standard.bool(forKey: nearbyKey) }
    static var balanceEnabled: Bool { UserDefaults.standard.object(forKey: balanceKey) as? Bool ?? true }
    static var balanceInterval: Interval {
        UserDefaults.standard.string(forKey: balanceIntervalKey).flatMap(Interval.init(rawValue:)) ?? .month
    }
    static var channel: Channel {
        UserDefaults.standard.string(forKey: channelKey).flatMap(Channel.init(rawValue:)) ?? .push
    }

    /// Meldingen op dit apparaat: altijd, behalve als je alleen e-mail koos (en een account hebt).
    @MainActor static var pushEnabled: Bool { channel != .mail || !AccountService.shared.isSignedIn }

    enum Interval: String, CaseIterable, Identifiable {
        case week, month, quarter
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week: String(localized: "Elke week")
            case .month: String(localized: "Elke maand")
            case .quarter: String(localized: "Elk kwartaal")
            }
        }

        /// De volgende momenten (10:00): zaterdag, de 1e van de maand of de 1e van januari, april, juli en oktober.
        /// De mails van de server volgen hetzelfde ritme.
        func nextDates(after now: Date = .now, count: Int, calendar: Calendar = .current) -> [Date] {
            var result: [Date] = []
            var components: DateComponents
            switch self {
            case .week: components = DateComponents(hour: 10, minute: 0, weekday: 7)
            case .month, .quarter: components = DateComponents(day: 1, hour: 10, minute: 0)
            }
            var cursor = now
            while result.count < count {
                guard let next = calendar.nextDate(after: cursor, matching: components, matchingPolicy: .nextTime) else { break }
                cursor = next
                if self == .quarter, ![1, 4, 7, 10].contains(calendar.component(.month, from: next)) { continue }
                result.append(next)
            }
            return result
        }
    }

    enum Channel: String, CaseIterable, Identifiable {
        case push, mail, both
        var id: String { rawValue }
        var title: String {
            switch self {
            case .push: String(localized: "Pushmelding")
            case .mail: String(localized: "E-mail")
            case .both: String(localized: "Beide")
            }
        }
        var symbol: String {
            switch self {
            case .push: "bell.fill"
            case .mail: "envelope.fill"
            case .both: "bell.and.waves.left.and.right.fill"
            }
        }
    }

    /// Asks for permission to show notifications (once; iOS remembers the answer).
    @discardableResult
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Cadeaukaarten die meetellen voor de tegoed-herinnering: tegoed boven nul, niet verlopen, niet tijdelijk gedeeld.
    static func balanceCards(_ cards: [Card]) -> [Card] {
        cards.filter { $0.deletedAt == nil && $0.kind == .voucher && ($0.balance ?? 0) > 0 && !$0.isExpired && !$0.isTemporary }
            .alphabetical()
    }

    /// "Je hebt nog € 25,00 bij Bol" of, bij meer kaarten, het totaal met de grootste tegoeden.
    static func balanceMessage(_ cards: [Card]) -> (title: String, body: String)? {
        let list = balanceCards(cards)
        guard let first = list.first else { return nil }
        func money(_ c: Card) -> String { CardAppearance(c).balanceText ?? "" }
        if list.count == 1 {
            let expiry = first.expiresAt.map { String(localized: " Geldig tot \($0.formatted(date: .abbreviated, time: .omitted)).") } ?? ""
            return (String(localized: "Je hebt nog \(money(first)) bij \(first.storeName)"),
                    String(localized: "Vergeet je cadeaukaart niet.") + expiry)
        }
        let codes = Set(list.map { $0.currencyCode ?? "EUR" })
        let top = list.sorted { ($0.balance ?? 0) > ($1.balance ?? 0) }.prefix(3)
        var body = top.map { "\($0.storeName) \(money($0))" }.joined(separator: ", ")
        if list.count > 3 { body += String(localized: " en \(list.count - 3) meer") }
        if codes.count == 1, let code = codes.first {
            let total = list.reduce(0) { $0 + ($1.balance ?? 0) }.formatted(.currency(code: code))
            return (String(localized: "Je hebt nog \(total) tegoed op \(list.count) cadeaukaarten"), body)
        }
        return (String(localized: "Je hebt nog tegoed op \(list.count) cadeaukaarten"), body)
    }

    // MARK: Plannen

    /// Plant alle herinneringen opnieuw (goedkoop; gebeurt als kaarten veranderen): vervaldatums van vouchers en
    /// kortingscodes, verlengingen van abonnementen en de tegoed-herinnering.
    @MainActor
    static func rescheduleVouchers(_ cards: [Card]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix("voucher-") || $0.hasPrefix("balance-") || $0.hasPrefix("renew-") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard pushEnabled else { return }
        let live = cards.filter { $0.deletedAt == nil && !$0.isTemporary }
        let expiring = vouchersEnabled ? live.filter { $0.kind.hasExpiry && $0.expiresAt != nil } : []
        let renewing = vouchersEnabled ? live.filter { $0.kind == .subscription && $0.details.renewsAt != nil } : []
        let balance = balanceEnabled ? balanceMessage(live) : nil
        guard !expiring.isEmpty || !renewing.isEmpty || balance != nil else { return }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined { await requestPermission() }

        let calendar = Calendar.current
        func add(_ id: String, title: String, body: String, at fire: Date, card: Card?, thread: String) async {
            guard fire > .now else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            if let card { content.userInfo = ["cardID": card.id.uuidString] }
            content.threadIdentifier = thread
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        for card in expiring {
            guard let expires = card.expiresAt else { continue }
            let day = calendar.startOfDay(for: expires)
            let balance = card.kind == .voucher ? CardAppearance(card).balanceText : nil
            let isCode = card.kind == .code
            let moments: [(Int, String, String)] = [
                (-7, isCode ? String(localized: "Kortingscode \(card.storeName) verloopt over een week")
                            : String(localized: "\(card.storeName) verloopt over een week"),
                 balance.map { String(localized: "Je hebt nog \($0) tegoed. Gebruik je kaart op tijd.") }
                    ?? (isCode ? String(localized: "Gebruik je code op tijd.") : String(localized: "Gebruik je kaart op tijd."))),
                (0, isCode ? String(localized: "Kortingscode \(card.storeName) verloopt vandaag")
                           : String(localized: "\(card.storeName) verloopt vandaag"),
                 balance.map { String(localized: "Laatste dag om je \($0) te gebruiken.") }
                    ?? (isCode ? String(localized: "Laatste dag om je code te gebruiken.") : String(localized: "Laatste dag om je kaart te gebruiken."))),
            ]
            for (offset, title, body) in moments {
                guard let date = calendar.date(byAdding: .day, value: offset, to: day),
                      let fire = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: date) else { continue }
                await add("voucher-\(card.id.uuidString)-\(offset)", title: title, body: body, at: fire, card: card, thread: "vouchers")
            }
        }

        for card in renewing {
            guard let renews = card.details.renewsAt,
                  let date = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: renews)),
                  let fire = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: date) else { continue }
            let appearance = CardAppearance(card)
            let cost = card.details.cost.map { $0.formatted(.currency(code: card.currencyCode ?? "EUR")) }
            await add("renew-\(card.id.uuidString)",
                      title: String(localized: "\(card.storeName) verlengt over 2 dagen"),
                      body: cost.map { String(localized: "Je betaalt dan \($0). Opzeggen? Doe het op tijd.") }
                        ?? (appearance.infoLine ?? String(localized: "Opzeggen? Doe het op tijd.")),
                      at: fire, card: card, thread: "subscriptions")
        }

        if let balance {
            let single = balanceCards(live).count == 1 ? balanceCards(live).first : nil
            for (i, fire) in balanceInterval.nextDates(count: 3).enumerated() {
                await add("balance-\(i)", title: balance.title, body: balance.body, at: fire, card: single, thread: "balance")
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
    /// Pushmelding "Nieuws over mijn kaarten" of een bericht aan iedereen (kind "news"): RootView opent je kaart van die
    /// winkel, of anders Kaart toevoegen bij die winkel; zonder winkel met een https-link die link (pasr.nl-links op de
    /// juiste plek in Pasr, andere in Safari in de app).
    @MainActor static var pendingNews: (store: String?, url: URL?)? {
        didSet { if pendingNews != nil { NotificationCenter.default.post(name: .pasrOpenNews, object: nil) } }
    }

    /// Garantieherinnering of Spotlight: WalletView opent dat bonnetje.
    @MainActor static var pendingReceiptID: UUID? {
        didSet { if pendingReceiptID != nil { NotificationCenter.default.post(name: .pasrOpenReceipt, object: nil) } }
    }

    func activate() {
        UNUserNotificationCenter.current().delegate = self
        PurchaseCapture.registerCategories()
    }

    // Met completion handlers in plaats van async: de async-varianten roepen de afhandeling van iOS niet op de
    // hoofdthread aan, en dan crasht de app bij het openen van een melding.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        // aankoop via Opdrachten bij een cadeaukaart: afboeken of niet, zonder de app te openen
        if response.actionIdentifier == PurchaseCapture.bookAction || response.actionIdentifier == PurchaseCapture.skipAction,
           let card = (info["cardID"] as? String).flatMap(UUID.init), let use = (info["useID"] as? String).flatMap(UUID.init) {
            let book = response.actionIdentifier == PurchaseCapture.bookAction
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let context = PasrStore.app.mainContext
                    if book { PurchaseCapture.book(cardID: card, useID: use, in: context) }
                    else { PurchaseCapture.skip(cardID: card, useID: use, in: context) }
                }
                completionHandler()
            }
            return
        }
        // garantieherinnering: dat bonnetje openen
        if let receipt = (info["receiptID"] as? String).flatMap(UUID.init) {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Self.pendingReceiptID = receipt }
                completionHandler()
            }
            return
        }
        let cardID = (info["cardID"] as? String).flatMap(UUID.init)
        let kind = info["kind"] as? String
        let storeID = kind == "store" ? info["store"] as? String : nil
        let newsStore = kind == "news" ? (info["store"] as? String).flatMap { $0.isEmpty ? nil : $0 } : nil
        // link onder de melding (bericht uit het beheer): alleen https
        let link = (info["url"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let cardID { Self.pendingCardID = cardID }
                else if let storeID { Self.pendingStoreID = storeID }
                else if kind == "news" { Self.pendingNews = (newsStore, link) }
                else if let link { Self.pendingNews = (nil, link) }
            }
            completionHandler()
        }
    }

    /// Also show them while Pasr is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

extension Notification.Name {
    static let pasrOpenCard = Notification.Name("pasrOpenCard")
    static let pasrOpenStore = Notification.Name("pasrOpenStore")
    static let pasrOpenNews = Notification.Name("pasrOpenNews")
    static let pasrOpenReceipt = Notification.Name("pasrOpenReceipt")
    /// Een Pasr-link die in de app zelf is gescand (object: URL); RootView behandelt hem als een universal link.
    static let pasrOpenLink = Notification.Name("pasrOpenLink")
    /// Sluit open vensters (voor een binnenkomende link).
    static let pasrCloseSheets = Notification.Name("pasrCloseSheets")
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

/// Settings: herinneringen (vervaldatums, tegoed; push of e-mail) en de kaart bij de winkel.
struct RemindersSettingsSection: View {
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @AppStorage(Reminders.voucherKey) private var vouchers = true
    @AppStorage(Reminders.balanceKey) private var balance = true
    @AppStorage(Reminders.balanceIntervalKey) private var interval = Reminders.Interval.month.rawValue
    @AppStorage(Reminders.channelKey) private var channel = Reminders.Channel.push.rawValue
    @AppStorage(Reminders.nearbyKey) private var nearby = false
    @AppStorage(UserPush.newStoresKey) private var newStores = false
    @AppStorage(StorePush.key) private var cardNews = false
    @State private var note: String?
    @State private var savingChannel = false
    private var stores: NearbyStores { .shared }
    private var account: AccountService { .shared }

    private func remindersChanged() {
        Task {
            await Reminders.rescheduleVouchers(cards)
            await MailReminders.syncIfMailing()
        }
    }

    private var channelBinding: Binding<String> {
        Binding(get: { account.isSignedIn ? channel : Reminders.Channel.push.rawValue }, set: { new in
            let old = channel
            channel = new
            savingChannel = true
            Task {
                defer { savingChannel = false }
                do {
                    try await MailReminders.save(enabled: new != Reminders.Channel.push.rawValue)
                    note = nil
                } catch {
                    channel = old
                    note = error.localizedDescription
                }
                await Reminders.rescheduleVouchers(cards)
            }
        })
    }

    var body: some View {
        Section {
            Toggle(isOn: $vouchers) {
                SettingsLabel("Vervaldatums en verlengingen", symbol: "bell.badge.fill", color: .red)
            }
            .onChange(of: vouchers) { _, _ in remindersChanged() }

            Toggle(isOn: $balance) {
                SettingsLabel("Tegoed-herinnering", symbol: "eurosign.circle.fill", color: Brand.mint)
            }
            .onChange(of: balance) { _, _ in remindersChanged() }
            if balance {
                Picker(selection: $interval) {
                    ForEach(Reminders.Interval.allCases) { Text($0.title).tag($0.rawValue) }
                } label: {
                    SettingsLabel("Hoe vaak", symbol: "calendar", color: .orange)
                }
                .onChange(of: interval) { _, _ in remindersChanged() }
            }

            if account.isSignedIn {
                Picker(selection: channelBinding) {
                    ForEach(Reminders.Channel.allCases) { c in
                        Label(c.title, systemImage: c.symbol).tag(c.rawValue)
                    }
                } label: {
                    HStack {
                        SettingsLabel("Herinneren via", symbol: "envelope.badge.fill", color: Brand.iris)
                        if savingChannel { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(savingChannel)
            }
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
                        SettingsLabel("Locatie: Altijd", symbol: "location.circle.fill", color: .blue)
                    }
                } else {
                    Button { stores.requestAlways() } label: {
                        HStack {
                            SettingsLabel("Locatie: Altijd", symbol: "location.circle", color: .orange)
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
            // ook zonder account (pasr_news_register)
            Toggle(isOn: Binding(get: { cardNews }, set: { on in
                cardNews = on
                Task {
                    if let problem = await StorePush.setEnabled(on, cards: cards) {
                        cardNews = StorePush.isEnabled
                        note = problem
                    } else {
                        note = nil
                    }
                }
            })) {
                SettingsLabel("Nieuws over mijn kaarten", symbol: "megaphone.fill", color: .orange)
            }
        } header: {
            Text("Meldingen")
        } footer: {
            Text(note ?? footer)
        }
        .task { await MailReminders.refreshChannel() }
    }

    private var remindersFooter: String {
        let balanceText = balance
            ? String(localized: "Heb je tegoed op een cadeaukaart, ook zonder vervaldatum, dan krijg je \((Reminders.Interval(rawValue: interval) ?? .month).title.lowercased()) een seintje. ")
            : ""
        guard account.isSignedIn else {
            return balanceText + String(localized: "Herinneringen ook per e-mail? Dat kan met een Pasr-account.")
        }
        switch Reminders.Channel(rawValue: channel) ?? .push {
        case .push: return balanceText
        case .mail: return balanceText + String(localized: "Je krijgt de herinneringen per e-mail van support@pasr.nl, niet als melding op dit apparaat. Alleen je eigen kaarten in je account tellen mee, niet die in een gedeelde Pasr.")
        case .both: return balanceText + String(localized: "Je krijgt de herinneringen als melding en per e-mail van support@pasr.nl. Voor e-mail tellen alleen je eigen kaarten in je account mee, niet die in een gedeelde Pasr.")
        }
    }

    private var footer: String {
        var text = remindersFooter + (remindersFooter.isEmpty ? "" : "\n\n") + nearbyFooter
        do {
            text += "\n\n" + String(localized: "Met Nieuws over mijn kaarten krijg je af en toe een bericht van Pasr over winkels waarvan je een kaart hebt, zoals een nieuwe actie. Pasr weet daarvoor alleen welke winkels in je Pasr staan, geen kaartnummers.")
        }
        return text
    }

    private var nearbyFooter: String {
        guard nearby else {
            return String(localized: "Sta je bij een winkel, dan verschijnt je kaart met een melding. Je locatie blijft op je iPhone.")
        }
        if stores.hasAlways {
            return String(localized: "Je krijgt een melding als je binnen 5 meter van de winkel bent, niet als je langsrijdt. Eén winkel tegelijk, en dezelfde winkel hoogstens eens per 4 uur. Je locatie blijft op je iPhone.")
        }
        return String(localized: "Zet je locatie voor Pasr op \u{201C}Altijd\u{201D}. Alleen dan kan Pasr nagaan of je echt bij de winkel bent en niet alleen in de buurt. Je locatie blijft op je iPhone.")
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
                Text("Winkels die dicht bij elkaar liggen delen een gebied; iOS bewaakt er hoogstens 20. Eigen locaties gaan voor en zijn het preciest: zet je vaste filiaal vast bij een kaart onder Wijzig › Locaties › Ik sta hier.")
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
