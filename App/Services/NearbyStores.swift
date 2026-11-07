import Foundation
import UserNotifications
import CoreLocation
import MapKit
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// "Kaart tonen bij de winkel". iOS laat een app hoogstens 20 plekken tegelijk bewaken; Pasr kiest de 20 beste plekken
/// rond waar je bent en laat iOS een melding geven als je er binnenloopt:
/// - eerst je eigen locaties (Ik sta hier / speld op de kaart), daarna filialen uit Apple Kaarten;
/// - per keten meer filialen als je weinig verschillende winkels hebt;
/// - met de toestemming "Altijd" wekt iOS Pasr na zo'n kilometer verplaatsen (significante locatiewijziging) en zet
///   Pasr de plekken opnieuw klaar, ook als je Pasr niet opent. Zonder die toestemming gebeurt dat bij het openen.
/// Alles gebeurt op de iPhone; je locatie gaat nergens heen.
@MainActor
@Observable
final class NearbyStores: NSObject, CLLocationManagerDelegate {
    static let shared = NearbyStores()

    static let radius: CLLocationDistance = 150
    private static let maxPlaces = 20
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
    }

    /// Zet het aan: vraagt om meldingen en locatie en plant de plekken.
    func enable(cards: [Card]) async -> Bool {
        UserDefaults.standard.set(true, forKey: Reminders.nearbyKey)
        guard await Reminders.requestPermission() else { return false }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        await refresh(cards: cards, force: true)
        updateBackgroundWatching()
        return hasLocation
    }

    func disable() async {
        UserDefaults.standard.set(false, forKey: Reminders.nearbyKey)
        manager.stopMonitoringSignificantLocationChanges()
        await removeNotifications()
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

        // Eerst eigen locaties (hoogstens 10), dan filialen: per keten een eerlijk deel, de rest naar de dichtstbijzijnde.
        var chosen = own.sorted { $0.1 < $1.1 }.prefix(10).map(\.0)
        let room = Self.maxPlaces - chosen.count
        let stores = Set(found.map(\.0.store)).count
        let perStore = max(3, stores == 0 ? room : Int((Double(room) / Double(stores)).rounded(.up)))
        var count: [String: Int] = [:]
        var rest: [Watched] = []
        for (place, _) in found.sorted(by: { $0.1 < $1.1 }) {
            count[place.store, default: 0] += 1
            if count[place.store]! <= perStore { rest.append(place) }
        }
        chosen += rest.prefix(room)

        await schedule(chosen)
        lastLocation = here
        lastPlan = .now
        UserDefaults.standard.set(["lat": here.coordinate.latitude, "lon": here.coordinate.longitude,
                                   "at": Date.now.timeIntervalSince1970], forKey: Self.planKey)
    }

    private func schedule(_ places: [Watched]) async {
        await removeNotifications()
        let center = UNUserNotificationCenter.current()
        for (index, place) in places.enumerated() {
            let region = CLCircularRegion(center: place.coordinate, radius: Self.radius, identifier: "nearby-\(index)")
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
        watched = places
        saveWatched()
    }

    private func removeNotifications() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("nearby-") }
        center.removePendingNotificationRequests(withIdentifiers: ids)
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
            self.authorization = status
            self.updateBackgroundWatching()
        }
    }

    private func received(_ location: CLLocation) {
        if !waiting.isEmpty {
            let list = waiting
            waiting = []
            list.forEach { $0.resume(returning: location) }
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
