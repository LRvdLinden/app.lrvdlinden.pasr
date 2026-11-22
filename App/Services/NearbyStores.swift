import Foundation
import UserNotifications
import CoreLocation
import MapKit
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// "Kaart tonen bij de winkel", in twee stappen:
/// 1. Grof: iOS bewaakt hoogstens 20 gebieden per app. Pasr kiest de beste winkels rond waar je bent (eerst je eigen
///    locaties, daarna filialen uit Apple Kaarten) en voegt winkels die dicht bij elkaar liggen (een winkelcentrum)
///    samen tot één gebied. Kom je in zo'n gebied, dan wekt iOS Pasr; er gaat dan nog geen melding uit.
/// 2. Precies: Pasr meet je plek met de nauwkeurigste GPS, een halve minuut lang. Alleen als je stilstaat of loopt
///    (niet rijdt) en binnen 5 meter van een winkel bent (plus de foutmarge van de GPS) komt er één melding, voor de
///    dichtstbijzijnde winkel. Dezelfde winkel meldt zich daarna 4 uur niet, en twee meldingen vlak na elkaar kan niet.
/// Met de toestemming "Altijd" wekt iOS Pasr ook na zo'n kilometer verplaatsen en zet Pasr de gebieden opnieuw klaar.
/// Alles gebeurt op de iPhone; je locatie gaat nergens heen.
@MainActor
@Observable
final class NearbyStores: NSObject, CLLocationManagerDelegate {
    static let shared = NearbyStores()

    /// Twee plekken binnen deze afstand zijn hetzelfde filiaal (eigen locatie en Kaarten-filiaal, of dubbel in Kaarten).
    static let radius: CLLocationDistance = 60
    /// Zo dichtbij moet je zijn voor een melding.
    static let confirmDistance: CLLocationDistance = 5
    /// Een filiaal uit Apple Kaarten is één punt in een gebouw; de ingang kan verder weg liggen dan bij een eigen speld.
    private static let mapsMargin: CLLocationDistance = 15
    /// Hoogstens zoveel van de GPS-foutmarge telt mee (binnen is GPS minder precies).
    private static let maxAccuracyMargin: CLLocationDistance = 25
    /// Een meting die onnauwkeuriger is dan dit gebruikt Pasr niet: dan liever geen melding dan een verkeerde.
    private static let usableAccuracy: CLLocationAccuracy = 50
    /// Sneller dan dit (ongeveer 9 km/u) = je rijdt of fietst langs: geen melding.
    private static let maxSpeed: CLLocationSpeed = 2.5
    /// Zo lang meet Pasr na het binnenkomen van een gebied.
    private static let checkDuration: TimeInterval = 25
    /// Dezelfde winkel niet opnieuw binnen deze tijd.
    private static let storeCooldown: TimeInterval = 4 * 3600
    /// Twee meldingen (van verschillende winkels) niet vlak na elkaar.
    private static let anyCooldown: TimeInterval = 120
    /// iOS bewaakt hoogstens 20 gebieden per app.
    private static let maxRegions = 20
    /// Winkels per gebied samen: zo ver uit elkaar mogen ze liggen.
    private static let clusterSpan: CLLocationDistance = 80
    /// Kleinste gebied dat iOS betrouwbaar bewaakt.
    private static let regionRadius: CLLocationDistance = 100
    private static let maxPlaces = 40
    private static let replanDistance: CLLocationDistance = 1_000
    private static let searchSpan: CLLocationDistance = 15_000
    private static let cacheReuse: CLLocationDistance = 4_000
    private static let cacheAge: TimeInterval = 14 * 86_400

    /// Een bewaakte plek, voor het overzicht in Instellingen.
    struct Watched: Codable, Identifiable, Hashable {
        var id: String { "\(store)|\(latitude)|\(longitude)" }
        var store: String
        var name: String
        var cardID: UUID
        var latitude: Double
        var longitude: Double
        var own: Bool
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    /// Een filiaal uit Apple Kaarten.
    struct Branch: Codable, Hashable, Identifiable {
        var id: String { "\(latitude)|\(longitude)" }
        var name: String
        var address: String?
        var latitude: Double
        var longitude: Double
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
        func distance(from here: CLLocation) -> CLLocationDistance {
            here.distance(from: CLLocation(latitude: latitude, longitude: longitude))
        }
    }

    /// Per winkel waarvoor je een kaart hebt: welke kaart opent en je eigen locaties. Bewaard, zodat Pasr ook op de
    /// achtergrond (zonder database) opnieuw kan plannen.
    struct Source: Codable {
        var name: String
        var cardID: UUID
        var places: [CardPlace]
    }

    private struct SearchCache: Codable {
        var latitude: Double
        var longitude: Double
        var at: Date
        var branches: [Branch]
    }

    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []
    private var planning = false

    private(set) var authorization: CLAuthorizationStatus
    private(set) var watched: [Watched] = []
    private(set) var lastPlan: Date?
    private(set) var lastLocation: CLLocation?

    var placesWatched: Int { watched.count }
    var hasAlways: Bool { authorization == .authorizedAlways }
    var hasLocation: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }

    private static let watchedKey = "pasr.nearby.watched"
    private static let sourcesKey = "pasr.nearby.sources"
    private static let cacheKey = "pasr.nearby.cache"
    private static let planKey = "pasr.nearby.plan"
    private static let shownKey = "pasr.nearby.shown"
    private static let regionPrefix = "pasr.nearby."

    /// Na het binnenkomen van een gebied: tot wanneer Pasr nauwkeurig meet.
    private var checkUntil: Date?
    #if canImport(UIKit)
    private var checkTask = UIBackgroundTaskIdentifier.invalid
    #endif

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if let data = UserDefaults.standard.data(forKey: Self.watchedKey),
           let list = try? JSONDecoder().decode([Watched].self, from: data) { watched = list }
        if let plan = UserDefaults.standard.dictionary(forKey: Self.planKey),
           let lat = plan["lat"] as? Double, let lon = plan["lon"] as? Double, let at = plan["at"] as? Double {
            lastLocation = CLLocation(latitude: lat, longitude: lon)
            lastPlan = Date(timeIntervalSince1970: at)
        }
    }

    // MARK: Aan en uit

    /// Bij het opstarten (ook als iOS Pasr op de achtergrond start na een verplaatsing): weer meeluisteren.
    func resume() {
        updateBackgroundWatching()
        Task { await removeLegacyNotifications() }
    }

    /// Zet het aan: vraagt om meldingen en locatie en plant de plekken.
    func enable(cards: [Card]) async -> Bool {
        UserDefaults.standard.set(true, forKey: Reminders.nearbyKey)
        guard await Reminders.requestPermission() else { return false }
        // Gebieden bewaken kan alleen met "Altijd". iOS vraagt eerst "Bij gebruik" en later zelf om Altijd.
        if manager.authorizationStatus == .notDetermined || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
            for _ in 0..<60 where manager.authorizationStatus == .notDetermined { try? await Task.sleep(for: .milliseconds(500)) }
        }
        await refresh(cards: cards, force: true)
        updateBackgroundWatching()
        return hasLocation
    }

    func disable() async {
        UserDefaults.standard.set(false, forKey: Reminders.nearbyKey)
        manager.stopMonitoringSignificantLocationChanges()
        stopRegions()
        await removeLegacyNotifications()
        watched = []
        saveWatched()
    }

    /// "Ook als Pasr dicht is": vraagt om Altijd. Was dat al eens geweigerd, dan opent Instellingen.
    func requestAlways() {
        if authorization == .authorizedWhenInUse || authorization == .notDetermined {
            manager.requestAlwaysAuthorization()
        } else {
            #if canImport(UIKit)
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            #endif
        }
    }

    private func updateBackgroundWatching() {
        if Reminders.nearbyEnabled, hasAlways, CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
    }

    // MARK: Plannen

    /// Vanuit de app (openen, omlaag trekken, kaarten gewijzigd): bronnen bijwerken en, als je verplaatst bent of
    /// het een uur geleden is, de plekken opnieuw kiezen.
    func refresh(cards: [Card], force: Bool = false) async {
        saveSources(from: cards)
        guard Reminders.nearbyEnabled, hasLocation, let here = await currentLocation(maxAge: force ? 60 : 600) else { return }
        let moved = lastLocation.map { here.distance(from: $0) } ?? .infinity
        let age = lastPlan.map { Date.now.timeIntervalSince($0) } ?? .infinity
        guard force || moved > 300 || age > 3600 else { return }
        await plan(around: here, allowSearch: true)
    }

    /// Alleen de bronnen opslaan (bijvoorbeeld na het wijzigen van eigen locaties), daarna opnieuw plannen.
    func sourcesChanged(cards: [Card]) async {
        saveSources(from: cards)
        guard Reminders.nearbyEnabled, let here = lastLocation ?? manager.location else { return }
        await plan(around: here, allowSearch: false)
    }

    /// Voor "Dichtstbij eerst" zonder meldingen: filialen rond je opzoeken (alleen wat nog niet bekend is).
    func updateBranches(cards: [Card]) async -> CLLocation? {
        saveSources(from: cards)
        guard hasLocation, let here = await currentLocation(maxAge: 120) else { return nil }
        if Reminders.nearbyEnabled {
            await plan(around: here, allowSearch: true)
            return here
        }
        var cache = loadCache()
        var left = 40
        for source in loadSources() where left > 0 {
            if let hit = cache[Self.key(source.name)],
               here.distance(from: CLLocation(latitude: hit.latitude, longitude: hit.longitude)) < Self.cacheReuse,
               Date.now.timeIntervalSince(hit.at) < Self.cacheAge { continue }
            left -= 1
            let branches = await search(source.name, around: here.coordinate, span: Self.searchSpan)
            cache[Self.key(source.name)] = SearchCache(latitude: here.coordinate.latitude, longitude: here.coordinate.longitude,
                                                       at: .now, branches: branches)
        }
        saveCache(cache)
        return here
    }

    private func plan(around here: CLLocation, allowSearch: Bool) async {
        guard !planning else { return }
        planning = true
        defer { planning = false }

        let sources = loadSources()
        var cache = loadCache()
        var own: [(Watched, CLLocationDistance)] = []
        var found: [(Watched, CLLocationDistance)] = []
        var searchesLeft = allowSearch ? 40 : 12

        for source in sources {
            for place in source.places {
                let d = here.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
                guard d < 60_000 else { continue }
                own.append((Watched(store: source.name, name: place.name.isEmpty ? source.name : place.name, cardID: source.cardID,
                                    latitude: place.latitude, longitude: place.longitude, own: true), d))
            }
            var branches: [Branch]
            if let hit = cache[Self.key(source.name)],
               here.distance(from: CLLocation(latitude: hit.latitude, longitude: hit.longitude)) < Self.cacheReuse,
               Date.now.timeIntervalSince(hit.at) < Self.cacheAge {
                branches = hit.branches
            } else if searchesLeft > 0 {
                searchesLeft -= 1
                branches = await search(source.name, around: here.coordinate, span: Self.searchSpan)
                cache[Self.key(source.name)] = SearchCache(latitude: here.coordinate.latitude, longitude: here.coordinate.longitude,
                                                           at: .now, branches: branches)
            } else {
                branches = cache[Self.key(source.name)]?.branches ?? []
            }
            for b in branches {
                // geen dubbele plek als je dit filiaal zelf al hebt vastgezet
                let isOwn = source.places.contains {
                    CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                        .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) < Self.radius
                }
                guard !isOwn else { continue }
                found.append((Watched(store: source.name, name: b.name, cardID: source.cardID,
                                      latitude: b.latitude, longitude: b.longitude, own: false), b.distance(from: here)))
            }
        }
        saveCache(cache)

        // Eerst eigen locaties (hoogstens 15), dan filialen: per keten een eerlijk deel, de rest naar de dichtstbijzijnde.
        // Dubbele plekken van dezelfde winkel (Kaarten noemt een filiaal soms twee keer) tellen één keer.
        var chosen: [Watched] = []
        func isDouble(_ p: Watched) -> Bool {
            chosen.contains { $0.store == p.store && Self.distance($0.coordinate, p.coordinate) < Self.radius }
        }
        for (place, _) in own.sorted(by: { $0.1 < $1.1 }) where chosen.count < 15 && !isDouble(place) { chosen.append(place) }
        let room = Self.maxPlaces - chosen.count
        let stores = Set(found.map(\.0.store)).count
        let perStore = max(3, stores == 0 ? room : Int((Double(room) / Double(stores)).rounded(.up)))
        var count: [String: Int] = [:]
        for (place, _) in found.sorted(by: { $0.1 < $1.1 }) where chosen.count < Self.maxPlaces && !isDouble(place) {
            count[place.store, default: 0] += 1
            if count[place.store]! <= perStore { chosen.append(place) }
        }

        await schedule(chosen)
        lastLocation = here
        lastPlan = .now
        UserDefaults.standard.set(["lat": here.coordinate.latitude, "lon": here.coordinate.longitude,
                                   "at": Date.now.timeIntervalSince1970], forKey: Self.planKey)
    }

    /// Gebieden voor iOS: winkels die dicht bij elkaar liggen (een winkelcentrum) delen één gebied, zodat ze samen
    /// maar één plek van de 20 gebruiken en je bij binnenkomst niet tien keer gewekt wordt.
    private func schedule(_ places: [Watched]) async {
        await removeLegacyNotifications()
        stopRegions()
        var clusters: [(center: CLLocationCoordinate2D, members: [Watched])] = []
        var kept: [Watched] = []
        for place in places {
            if let i = clusters.firstIndex(where: { Self.distance($0.center, place.coordinate) < Self.clusterSpan }) {
                clusters[i].members.append(place)
                kept.append(place)
            } else if clusters.count < Self.maxRegions {
                clusters.append((place.coordinate, [place]))
                kept.append(place)
            }
        }
        if hasAlways, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) {
            for (index, cluster) in clusters.enumerated() {
                let spread = cluster.members.map { Self.distance(cluster.center, $0.coordinate) }.max() ?? 0
                let radius = min(max(Self.regionRadius, spread + 60), manager.maximumRegionMonitoringDistance)
                let region = CLCircularRegion(center: cluster.center, radius: radius, identifier: "\(Self.regionPrefix)\(index)")
                region.notifyOnEntry = true
                region.notifyOnExit = false
                manager.startMonitoring(for: region)
            }
        }
        watched = kept
        saveWatched()
    }

    private func stopRegions() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.regionPrefix) {
            manager.stopMonitoring(for: region)
        }
    }

    /// Versies tot en met build 37 lieten iOS zelf een melding geven bij elk filiaal binnen 150 m. Weg ermee.
    private func removeLegacyNotifications() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("nearby-") }
        if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
    }

    // MARK: Echt bij de winkel?

    /// Je kwam in een gebied: meet een halve minuut nauwkeurig en kijk of je echt bij een winkel bent.
    private func startCheck() {
        guard Reminders.nearbyEnabled, hasAlways, !watched.isEmpty else { return }
        if let until = checkUntil, until > .now { return }   // meet al (meerdere gebieden tegelijk = één meting)
        checkUntil = Date.now.addingTimeInterval(Self.checkDuration)
        #if canImport(UIKit)
        if checkTask == .invalid {
            checkTask = UIApplication.shared.beginBackgroundTask(withName: "pasr.nearby.check") { [weak self] in
                MainActor.assumeIsolated { self?.stopCheck() }
            }
        }
        #endif
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.startUpdatingLocation()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.checkDuration + 1))
            if let until = self.checkUntil, until <= .now { self.stopCheck() }
        }
    }

    private func stopCheck() {
        checkUntil = nil
        manager.stopUpdatingLocation()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        #if canImport(UIKit)
        if checkTask != .invalid {
            UIApplication.shared.endBackgroundTask(checkTask)
            checkTask = .invalid
        }
        #endif
    }

    /// Eén meting tijdens de controle. Geeft de winkel waar je nu echt bij bent, of nil.
    static func storeAtHand(_ location: CLLocation, among places: [Watched]) -> Watched? {
        let accuracy = location.horizontalAccuracy
        guard accuracy >= 0, accuracy <= usableAccuracy else { return nil }
        if location.speed >= 0, location.speed > maxSpeed { return nil }
        let margin = min(accuracy, maxAccuracyMargin)
        return places
            .map { ($0, location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .filter { place, d in d <= confirmDistance + margin + (place.own ? 0 : mapsMargin) }
            .min { $0.1 < $1.1 }?.0
    }

    private func check(_ location: CLLocation) async {
        guard checkUntil != nil else { return }   // al klaar (een eerdere meting gaf de melding)
        // Rijden: stoppen met meten, langsrijden levert niets op.
        if location.speed >= 0, location.speed > Self.maxSpeed, location.horizontalAccuracy <= Self.usableAccuracy {
            stopCheck()
            return
        }
        guard let place = Self.storeAtHand(location, among: watched) else { return }
        stopCheck()
        var shown = UserDefaults.standard.dictionary(forKey: Self.shownKey) as? [String: Double] ?? [:]
        let now = Date.now.timeIntervalSince1970
        shown = shown.filter { now - $0.value < Self.storeCooldown }
        let key = Self.key(place.store)
        if let last = shown[key], now - last < Self.storeCooldown { return }
        if let latest = shown.values.max(), now - latest < Self.anyCooldown { return }
        shown[key] = now
        UserDefaults.standard.set(shown, forKey: Self.shownKey)

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Je bent bij \(place.store)")
        content.body = String(localized: "Tik om je kaart te tonen.")
        content.userInfo = ["cardID": place.cardID.uuidString]
        content.threadIdentifier = "nearby"
        content.interruptionLevel = .active
        content.relevanceScore = 1
        // Vaste id: een nieuwe melding vervangt de vorige in het berichtencentrum.
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ["nearby"])
        try? await center.add(UNNotificationRequest(identifier: "nearby", content: content, trigger: nil))
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    // MARK: Zoeken in Apple Kaarten

    /// Filialen van een winkel rond een punt, dichtstbijzijnde eerst.
    func search(_ store: String, around center: CLLocationCoordinate2D, span: CLLocationDistance = 25_000) async -> [Branch] {
        guard !store.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = store
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span)
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        let wanted = Self.squash(store)
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return response.mapItems
            .filter { item in
                // alleen echte filialen (Kaarten geeft ook plekken die de naam alleen noemen)
                guard let name = item.name else { return false }
                let n = Self.squash(name)
                return n.contains(wanted) || wanted.contains(n)
            }
            .map { item in
                let c = item.placemark.coordinate
                let p = item.placemark
                let address = [p.thoroughfare.map { street in [street, p.subThoroughfare].compactMap { $0 }.joined(separator: " ") }, p.locality]
                    .compactMap { $0 }.joined(separator: ", ")
                return Branch(name: item.name ?? store, address: address.isEmpty ? nil : address, latitude: c.latitude, longitude: c.longitude)
            }
            .sorted { $0.distance(from: here) < $1.distance(from: here) }
    }

    /// Filialen rond je huidige plek (voor de Wallet-pas). Leeg zonder locatietoegang; vraagt er nooit om.
    func branchesNearby(of store: String) async -> [Branch] {
        guard hasLocation, let here = await currentLocation(maxAge: 600) else { return [] }
        return Array(await search(store, around: here.coordinate).prefix(25))
    }

    /// Per kaart de afstand van hier tot het dichtstbijzijnde bekende filiaal of eigen locatie (zonder te zoeken).
    func knownDistances(for cards: [Card], from here: CLLocation) -> [UUID: CLLocationDistance] {
        let cache = loadCache()
        var out: [UUID: CLLocationDistance] = [:]
        for card in cards {
            var best: CLLocationDistance?
            for p in card.places {
                let d = here.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude))
                best = min(best ?? d, d)
            }
            let name = StoreTemplates.template(id: card.templateID)?.name ?? card.storeName
            for b in cache[Self.key(name)]?.branches ?? [] {
                let d = b.distance(from: here)
                best = min(best ?? d, d)
            }
            if let best { out[card.id] = best }
        }
        return out
    }

    /// Bij welk filiaal je nu bent (voor de geschiedenis): een eigen locatie of bekend filiaal binnen 300 m.
    /// Zonder locatietoegang nil; vraagt er nooit om.
    func placeName(for card: Card) async -> String? {
        guard hasLocation, let here = await currentLocation(maxAge: 300) else { return nil }
        let store = StoreTemplates.template(id: card.templateID)?.name ?? card.storeName
        var best: (CLLocationDistance, String)?
        for p in card.places {
            let d = here.distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude))
            let parts = p.name.components(separatedBy: " · ")
            let label = Self.label(name: parts.first ?? store, address: parts.count > 1 ? parts[1] : nil)
            if d < 300, d < (best?.0 ?? .infinity) { best = (d, label) }
        }
        for b in loadCache()[Self.key(store)]?.branches ?? [] {
            let d = b.distance(from: here)
            if d < 300, d < (best?.0 ?? .infinity) { best = (d, Self.label(name: b.name, address: b.address)) }
        }
        return best?.1
    }

    /// Plaats en provincie van waar je nu bent, voor "Laatst gebruikt" ("Apeldoorn", "Gelderland"). Nil zonder locatie.
    func area() async -> (city: String?, region: String?)? {
        guard hasLocation, let here = await currentLocation(maxAge: 300) else { return nil }
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(here, preferredLocale: Locale(identifier: "nl_NL")).first
        else { return nil }
        return (mark.locality, mark.administrativeArea)
    }

    /// "PLUS" + "Hoofdstraat 1, Apeldoorn" → "PLUS Apeldoorn".
    private static func label(name: String, address: String?) -> String {
        guard let city = address?.components(separatedBy: ", ").last?.trimmingCharacters(in: .whitespaces), !city.isEmpty,
              !name.localizedCaseInsensitiveContains(city) else { return name }
        return "\(name) \(city)"
    }

    /// Je plek nu (een recente is goed genoeg). Nil zonder toestemming.
    func currentLocation(maxAge: TimeInterval = 600) async -> CLLocation? {
        guard hasLocation else { return nil }
        if let recent = manager.location, Date.now.timeIntervalSince(recent.timestamp) < maxAge { return recent }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if waiting.count == 1 { manager.requestLocation() }
        }
    }

    /// Voor "Ik sta hier": vraagt om toestemming als dat nog niet is gebeurd.
    func locationForPin() async -> CLLocation? {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
            for _ in 0..<60 where authorization == .notDetermined { try? await Task.sleep(for: .milliseconds(500)) }
        }
        return await currentLocation(maxAge: 30)
    }

    // MARK: Opslag

    private static func key(_ store: String) -> String { squash(store) }

    /// "AH" en "Albert Heijn", "Kruidvat Apeldoorn" → alleen kleine letters en cijfers.
    static func squash(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func saveSources(from cards: [Card]) {
        var seen: [String: Int] = [:]
        var list: [Source] = []
        for card in cards.alphabetical() where card.deletedAt == nil && !card.isTemporary {
            let name = StoreTemplates.template(id: card.templateID)?.name ?? card.storeName
            guard !name.isEmpty else { continue }
            if let i = seen[Self.key(name)] {
                list[i].places += card.places.filter { p in !list[i].places.contains(p) }
                continue
            }
            // eigen kaarten zonder winkel alleen met eigen locaties (zoeken op "Mijn kaart" heeft geen zin)
            if StoreTemplates.template(id: card.templateID) == nil, card.places.isEmpty, name.lowercased().contains("eigen kaart") { continue }
            seen[Self.key(name)] = list.count
            list.append(Source(name: name, cardID: card.id, places: card.places))
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(list.prefix(60))), forKey: Self.sourcesKey)
    }

    private func loadSources() -> [Source] {
        UserDefaults.standard.data(forKey: Self.sourcesKey).flatMap { try? JSONDecoder().decode([Source].self, from: $0) } ?? []
    }

    private func loadCache() -> [String: SearchCache] {
        UserDefaults.standard.data(forKey: Self.cacheKey).flatMap { try? JSONDecoder().decode([String: SearchCache].self, from: $0) } ?? [:]
    }

    private func saveCache(_ cache: [String: SearchCache]) {
        let fresh = cache.filter { Date.now.timeIntervalSince($0.value.at) < Self.cacheAge }
        UserDefaults.standard.set(try? JSONEncoder().encode(fresh), forKey: Self.cacheKey)
    }

    private func saveWatched() {
        UserDefaults.standard.set(try? JSONEncoder().encode(watched), forKey: Self.watchedKey)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.received(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let list = self.waiting
            self.waiting = []
            list.forEach { $0.resume(returning: nil) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            let gotAlways = status == .authorizedAlways && self.authorization != .authorizedAlways
            self.authorization = status
            self.updateBackgroundWatching()
            // Net "Altijd" gekregen: de gebieden zetten (zonder Altijd bewaakt iOS ze niet).
            if gotAlways, Reminders.nearbyEnabled, !self.watched.isEmpty { await self.schedule(self.watched) }
            if status != .authorizedAlways { self.stopRegions() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("pasr.nearby.") else { return }
        Task { @MainActor in self.startCheck() }
    }

    private func received(_ location: CLLocation) {
        if !waiting.isEmpty {
            let list = waiting
            waiting = []
            list.forEach { $0.resume(returning: location) }
            if checkUntil == nil { return }
        }
        if let until = checkUntil {
            if until > .now { Task { await self.check(location) } } else { stopCheck() }
            return
        }
        // Significante verplaatsing (ook op de achtergrond): opnieuw plannen als je echt ergens anders bent.
        guard Reminders.nearbyEnabled else { return }
        let moved = lastLocation.map { location.distance(from: $0) } ?? .infinity
        guard moved > Self.replanDistance else { return }
        #if canImport(UIKit)
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "pasr.nearby") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        Task { @MainActor in
            await self.plan(around: location, allowSearch: true)
            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
        }
        #else
        Task { @MainActor in await self.plan(around: location, allowSearch: true) }
        #endif
    }
}
