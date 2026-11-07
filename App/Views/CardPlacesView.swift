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

/// Een filiaal of plek kiezen op de kaart: tik op een filiaal, of ergens op de kaart voor een speld.
struct PlacePickerView: View {
    let storeName: String
    /// Gekozen plek, of nil bij Annuleer. De ouder sluit het sheet.
    var onDone: (CardPlace?) -> Void
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(center: .init(latitude: 52.2, longitude: 5.4), latitudinalMeters: 250_000, longitudinalMeters: 250_000))
    @State private var branches: [NearbyStores.Branch] = []
    @State private var selected: NearbyStores.Branch?
    @State private var pin: CLLocationCoordinate2D?
    @State private var query = ""
    @State private var center: CLLocationCoordinate2D?
    @State private var searching = false

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()
                    ForEach(branches) { b in
                        Annotation(b.name, coordinate: b.coordinate) {
                            Image(systemName: "storefront.circle.fill")
                                .font(selected == b ? .largeTitle : .title)
                                .foregroundStyle(.white, selected == b ? Brand.coral : Brand.iris)
                                .onTapGesture { selected = b; pin = nil }
                        }
                    }
                    if let pin {
                        Marker(storeName, systemImage: "mappin", coordinate: pin).tint(Brand.coral)
                    }
                }
                .mapControls { MapUserLocationButton(); MapCompass() }
                .onTapGesture { point in
                    if let c = proxy.convert(point, from: .local) { pin = c; selected = nil }
                }
                .onMapCameraChange(frequency: .onEnd) { context in center = context.region.center }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("Kies een locatie")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $query, prompt: Text("Zoek een plaats of adres"))
            .onSubmit(of: .search) { Task { await searchPlace() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { onDone(nil) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Voeg toe") { add() }.disabled(selected == nil && pin == nil)
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
            if let selected {
                Text([selected.name, selected.address].compactMap { $0 }.joined(separator: " · ")).font(.subheadline.weight(.semibold))
            } else if pin != nil {
                Text("Speld gezet. Tik op Voeg toe.").font(.subheadline.weight(.semibold))
            } else {
                Text("Tik op een filiaal of ergens op de kaart.").font(.subheadline).foregroundStyle(.secondary)
            }
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
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.regularMaterial)
    }

    private func findBranches(around c: CLLocationCoordinate2D) async {
        searching = true
        defer { searching = false }
        branches = Array(await NearbyStores.shared.search(storeName, around: c, span: 12_000).prefix(25))
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
        if let selected {
            onDone(CardPlace(name: [selected.name, selected.address].compactMap { $0 }.joined(separator: " · "),
                             latitude: selected.latitude, longitude: selected.longitude))
        } else if let pin {
            onDone(CardPlace(name: storeName, latitude: pin.latitude, longitude: pin.longitude))
        } else {
            onDone(nil)
        }
    }
}
