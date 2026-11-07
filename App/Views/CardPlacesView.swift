import SwiftUI
import MapKit
import CoreLocation

/// Kaart wijzigen › Locaties: filialen die je zelf vastzet. Ze gaan voor bij "Kaart tonen bij de winkel" en komen
/// als eerste op de Wallet-pas. "Ik sta hier" neemt je plek nu; "Kies op de kaart" laat je een filiaal of een speld
/// kiezen.
struct CardPlacesSection: View {
    @Binding var places: [CardPlace]
    let storeName: String
    /// Opent de kaartkiezer. Het sheet hangt aan het formulier zelf (niet aan deze sectie): een sheet in een
    /// Form-rij verliest zijn plek als de rij verandert, en dan sluit ook het bewerkscherm.
    var onPickOnMap: () -> Void
    @State private var locating = false
    @State private var message: String?

    var body: some View {
        Section {
            ForEach(places) { place in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(place.name.isEmpty ? storeName : place.name)
                        Text(String(format: "%.4f, %.4f", place.latitude, place.longitude))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(Brand.coral)
                }
            }
            .onDelete { places.remove(atOffsets: $0) }

            if places.count < CardPlace.maxPerCard {
                Button {
                    Task { await hereNow() }
                } label: {
                    HStack {
                        Label("Ik sta hier", systemImage: "location.fill")
                        if locating { Spacer(); ProgressView() }
                    }
                }
                .disabled(locating)
                Button { onPickOnMap() } label: { Label("Kies op de kaart", systemImage: "map") }
            }
        } header: {
            Text("Locaties")
        } footer: {
            Text(message ?? String(localized: "Sta je bij je vaste filiaal? Zet het vast, dan verschijnt je kaart daar altijd. Tot \(CardPlace.maxPerCard) locaties; je locatie blijft op je iPhone."))
        }
    }

    private func hereNow() async {
        locating = true
        defer { locating = false }
        guard let here = await NearbyStores.shared.locationForPin() else {
            message = String(localized: "Pasr kan je locatie niet bepalen. Geef toegang in de Instellingen van je iPhone.")
            return
        }
        // Naam van het filiaal waar je staat, als Apple Kaarten dat kent
        let nearest = await NearbyStores.shared.search(storeName, around: here.coordinate, span: 2_000).first
        let name: String
        if let nearest, nearest.distance(from: here) < 250 {
            name = [nearest.name, nearest.address].compactMap { $0 }.joined(separator: " · ")
        } else {
            name = storeName
        }
        places.append(CardPlace(name: name, latitude: here.coordinate.latitude, longitude: here.coordinate.longitude))
        message = nil
    }
}

/// Filialen of plekken kiezen op de kaart, meerdere tegelijk: tik filialen aan (nog eens tikken = uit), of tik
/// ergens op de kaart voor een speld. "Alle" kiest de dichtstbijzijnde filialen tot het maximum.
struct PlacePickerView: View {
    let storeName: String
    /// Locaties die de kaart al heeft (staan op de kaart, tellen mee voor het maximum).
    var existing: [CardPlace] = []
    /// Gekozen plekken (leeg bij Annuleer). De ouder sluit het sheet.
    var onDone: ([CardPlace]) -> Void
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(center: .init(latitude: 52.2, longitude: 5.4), latitudinalMeters: 250_000, longitudinalMeters: 250_000))
    @State private var branches: [NearbyStores.Branch] = []
    @State private var selected: [NearbyStores.Branch] = []
    @State private var pins: [Pin] = []
    @State private var query = ""
    @State private var center: CLLocationCoordinate2D?
    @State private var searching = false

    private struct Pin: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }

    private var room: Int { max(0, CardPlace.maxPerCard - existing.count) }
    private var count: Int { selected.count + pins.count }
    private var full: Bool { count >= room }

    /// Filialen die de kaart al heeft, niet nog eens aanbieden.
    private var offered: [NearbyStores.Branch] {
        branches.filter { b in
            !existing.contains { CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) < NearbyStores.radius }
        }
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()
                    ForEach(existing) { place in
                        Annotation(place.name, coordinate: .init(latitude: place.latitude, longitude: place.longitude)) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title)
                                .foregroundStyle(.white, Brand.mint)
                        }
                    }
                    ForEach(offered) { b in
                        let on = selected.contains(b)
                        Annotation(b.name, coordinate: b.coordinate) {
                            Image(systemName: on ? "checkmark.circle.fill" : "storefront.circle.fill")
                                .font(on ? .largeTitle : .title)
                                .foregroundStyle(.white, on ? Brand.coral : Brand.iris)
                                .opacity(!on && full ? 0.45 : 1)
                                .onTapGesture { toggle(b) }
                                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                    ForEach(pins) { pin in
                        Annotation(storeName, coordinate: pin.coordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white, Brand.coral)
                                .onTapGesture { pins.removeAll { $0.id == pin.id } }
                        }
                    }
                }
                .mapControls { MapUserLocationButton(); MapCompass() }
                .onTapGesture { point in
                    guard !full, let c = proxy.convert(point, from: .local) else { return }
                    pins.append(Pin(coordinate: c))
                }
                .onMapCameraChange(frequency: .onEnd) { context in center = context.region.center }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("Kies locaties")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, prompt: Text("Zoek een plaats of adres"))
            .onSubmit(of: .search) { Task { await searchPlace() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { onDone([]) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(count > 1 ? String(localized: "Voeg \(count) toe") : String(localized: "Voeg toe")) { add() }
                        .disabled(count == 0)
                }
            }
            .task {
                if let here = await NearbyStores.shared.currentLocation(maxAge: 600) {
                    position = .region(MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 3_000, longitudinalMeters: 3_000))
                    center = here.coordinate
                    await findBranches(around: here.coordinate)
                }
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if room == 0 {
                Text("Deze kaart heeft al \(CardPlace.maxPerCard) locaties.").font(.subheadline.weight(.semibold))
            } else if count == 0 {
                Text("Tik filialen aan, of ergens op de kaart voor een speld.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("\(count) van \(room) gekozen").font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
            }
            HStack(spacing: 8) {
                Button {
                    Task { if let center { await findBranches(around: center) } }
                } label: {
                    HStack {
                        if searching { ProgressView().controlSize(.small) }
                        Text("Zoek \(storeName) hier")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(center == nil || searching)
                if !offered.isEmpty {
                    if selected.isEmpty {
                        Button("Alle") { selectNearest() }
                            .buttonStyle(.bordered)
                            .disabled(full)
                    } else {
                        Button("Wis keuze") { selected = []; pins = [] }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.regularMaterial)
        .animation(.snappy, value: count)
    }

    private func toggle(_ b: NearbyStores.Branch) {
        if let i = selected.firstIndex(of: b) { selected.remove(at: i) }
        else if !full { selected.append(b) }
    }

    /// De dichtstbijzijnde filialen (vanaf het midden van de kaart) tot het maximum.
    private func selectNearest() {
        let from = CLLocation(latitude: center?.latitude ?? 0, longitude: center?.longitude ?? 0)
        for b in offered.sorted(by: { $0.distance(from: from) < $1.distance(from: from) }) where !full && !selected.contains(b) {
            selected.append(b)
        }
    }

    private func findBranches(around c: CLLocationCoordinate2D) async {
        searching = true
        defer { searching = false }
        let found = await NearbyStores.shared.search(storeName, around: c, span: 12_000).prefix(25)
        // gekozen filialen blijven staan, ook als je verder schuift en opnieuw zoekt
        branches = selected + found.filter { !selected.contains($0) }
    }

    private func searchPlace() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return }
        let c = item.placemark.coordinate
        withAnimation { position = .region(MKCoordinateRegion(center: c, latitudinalMeters: 4_000, longitudinalMeters: 4_000)) }
        center = c
        await findBranches(around: c)
    }

    private func add() {
        let fromBranches = selected.map {
            CardPlace(name: [$0.name, $0.address].compactMap { $0 }.joined(separator: " · "), latitude: $0.latitude, longitude: $0.longitude)
        }
        let fromPins = pins.map { CardPlace(name: storeName, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        onDone(Array((fromBranches + fromPins).prefix(room)))
    }
}
