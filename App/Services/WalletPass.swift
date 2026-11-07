import SwiftUI
import PassKit
import CoreLocation
import MapKit

/// "Voeg toe aan Apple Wallet": the account server (function wallet-pass) turns the card into a signed Wallet
/// pass. The pass carries up to 10 nearby branches of the store, so iOS shows it on the lock screen there, like
/// any Wallet pass. Nothing is stored on the server.
enum WalletPass {
    static let passTypeID = "pass.nl.lrvdlinden.pasr"

    static let maxLocations = 10

    static func storeName(_ card: Card) -> String { StoreTemplates.template(id: card.templateID)?.name ?? card.storeName }

    static var isAvailable: Bool { PKAddPassesViewController.canAddPasses() && AccountConfig.isConfigured }

    /// Already in Wallet? (Same serial number = the card's id.)
    static func isInWallet(_ card: Card) -> Bool {
        PKPassLibrary().pass(withPassTypeIdentifier: passTypeID, serialNumber: card.id.uuidString) != nil
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// `locations`: de plekken waar iOS de pas laat zien (hoogstens 10). Nil = vanzelf: eigen locaties, dan de
    /// dichtstbijzijnde filialen.
    @MainActor
    static func make(for card: Card, locations: [CLLocationCoordinate2D]? = nil) async throws -> PKPass {
        guard !card.isTemporary else {
            throw Failure(message: String(localized: "Een tijdelijk gedeelde kaart kan niet in Apple Wallet."))
        }
        guard AccountConfig.isConfigured, let url = URL(string: "\(AccountConfig.url)/functions/v1/wallet-pass") else {
            throw Failure(message: String(localized: "Apple Wallet is in deze versie nog niet beschikbaar."))
        }
        var body: [String: Any] = [
            "id": card.id.uuidString, "name": card.storeName, "number": card.number, "format": card.formatRaw,
            "colorHex": card.colorHex, "kind": card.kindRaw,
        ]
        if !card.note.isEmpty { body["note"] = card.note }
        if let balance = card.balance { body["balance"] = balance; body["currency"] = card.currencyCode ?? "EUR" }
        if let expires = card.expiresAt { body["expiresAt"] = ISO8601DateFormatter().string(from: expires) }
        if let logo = logoPNG(for: card) { body["logo"] = logo.base64EncodedString() }
        let lines = historyLines(card)
        if !lines.isEmpty { body["history"] = lines }
        var spots = locations ?? savedLocations(card) ?? card.places.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        if locations == nil, spots.count < maxLocations {
            let branches = await NearbyStores.shared.branchesNearby(of: storeName(card))
            spots += branches.map(\.coordinate).prefix(maxLocations - spots.count)
        }
        if !spots.isEmpty {
            body["locations"] = spots.prefix(maxLocations).map { ["latitude": $0.latitude, "longitude": $0.longitude] }
        }
        saveLocations(Array(spots.prefix(maxLocations)), for: card)

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AccountConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: String(localized: "Geen verbinding. Controleer je internet en probeer het opnieuw."))
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let pass = try? PKPass(data: data) else {
            throw Failure(message: String(localized: "De Wallet-pas kon niet worden gemaakt. Probeer het later opnieuw."))
        }
        return pass
    }

    // MARK: Bijwerken

    /// Staat de kaart in Wallet, dan de pas daar vervangen door een nieuwe met het actuele tegoed en de laatste regels.
    /// Gaat zonder vraag (PKPassLibrary.replacePass); Wallet laat bij een nieuw tegoed zelf "Tegoed nu …" zien.
    @MainActor
    static func refreshIfInWallet(_ card: Card) async {
        guard isAvailable, !card.isTemporary, !card.number.isEmpty, isInWallet(card),
              let pass = try? await make(for: card, locations: savedLocations(card)) else { return }
        _ = PKPassLibrary().replacePass(with: pass)
    }

    private static func locationsKey(_ card: Card) -> String { "pasr.wallet.locations.\(card.id.uuidString)" }

    private static func saveLocations(_ spots: [CLLocationCoordinate2D], for card: Card) {
        UserDefaults.standard.set(spots.map { [$0.latitude, $0.longitude] }, forKey: locationsKey(card))
    }

    /// De plekken die bij het maken van de pas zijn gekozen (zodat bijwerken ze niet verandert).
    private static func savedLocations(_ card: Card) -> [CLLocationCoordinate2D]? {
        guard let list = UserDefaults.standard.array(forKey: locationsKey(card)) as? [[Double]] else { return nil }
        return list.compactMap { $0.count == 2 ? CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) : nil }
    }

    /// Achterkant van de pas: bij een voucher de laatste uitgaven en opwaarderingen, anders wanneer hij is getoond.
    static func historyLines(_ card: Card) -> [String] {
        let voucher = card.kind == .voucher
        let events = card.history.filter { voucher ? $0.kind != .shown : $0.kind == .shown }.prefix(6)
        return events.map { CardHistoryFormat.line($0, card: card) }
    }

    /// The logo as it appears on the card (store logo in its card style, or the owner's own), max 160×50 pt @3x.
    @MainActor
    private static func logoPNG(for card: Card) -> Data? {
        guard let data = card.logoData else { return nil }
        let style = card.logoFromWebsite ? StoreLogoStyles.style(for: card.logoDomain) : nil
        let renderer = ImageRenderer(content: StoreLogoMark(data: data, style: style, height: 50, maxWidth: 160, alignment: .leading)
            .frame(width: 160, height: 50, alignment: .leading))
        renderer.scale = 3
        renderer.isOpaque = false
        return renderer.uiImage?.pngData()
    }
}

/// Apple's own "Add to Apple Wallet" button. Eerst kies je waar de pas op je toegangsscherm verschijnt.
struct AddToWalletButton: View {
    let card: Card
    @State private var picking = false
    @State private var inWallet = false

    var body: some View {
        VStack(spacing: 8) {
            if inWallet {
                Label("Staat in Apple Wallet", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Brand.mint)
                Button("Locaties op de Wallet-pas wijzigen") { picking = true }
                    .font(.footnote)
            } else {
                WalletButton { picking = true }
                    .frame(height: 44)
                    .frame(maxWidth: 280)
            }
        }
        .onAppear { inWallet = WalletPass.isInWallet(card) }
        .sheet(isPresented: $picking, onDismiss: { inWallet = WalletPass.isInWallet(card) }) {
            WalletPlacesSheet(card: card)
        }
    }
}

/// Wallet-knop in het rijtje onder een kaart (zelfde glazen knop als de andere acties).
struct WalletActionButton: View {
    let card: Card
    @State private var picking = false

    var body: some View {
        Button {
            picking = true
        } label: {
            Label("Voeg toe aan Apple Wallet", systemImage: "wallet.pass")
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 30, height: 30)
        }
        .pasrGlassButton()
        .accessibilityLabel(Text("Voeg toe aan Apple Wallet"))
        .sheet(isPresented: $picking) { WalletPlacesSheet(card: card) }
    }
}

/// Waar moet de pas verschijnen? Eigen locaties en filialen in de buurt, hoogstens 10 (de grens van Apple Wallet).
/// iOS laat de pas op je toegangsscherm zien als je bij een van die plekken bent.
struct WalletPlacesSheet: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @State private var branches: [NearbyStores.Branch] = []
    @State private var chosen: Set<String> = []
    @State private var loading = true
    @State private var busy = false
    @State private var pass: PKPass?
    @State private var error: String?
    @State private var here: CLLocation?
    private var stores: NearbyStores { .shared }

    private struct Spot: Identifiable, Hashable {
        var id: String
        var title: String
        var detail: String?
        var coordinate: CLLocationCoordinate2D
        var own: Bool
        static func == (a: Spot, b: Spot) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    private var ownSpots: [Spot] {
        card.places.map { Spot(id: "own-\($0.id)", title: $0.name.isEmpty ? card.storeName : $0.name, detail: String(localized: "Eigen locatie"),
                               coordinate: .init(latitude: $0.latitude, longitude: $0.longitude), own: true) }
    }

    private var branchSpots: [Spot] {
        branches.filter { b in
            !card.places.contains { CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) < NearbyStores.radius }
        }
        .map { Spot(id: "map-\($0.id)", title: $0.name, detail: $0.address, coordinate: $0.coordinate, own: false) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !ownSpots.isEmpty {
                    Section("Eigen locaties") { ForEach(ownSpots) { row($0) } }
                }
                Section {
                    if loading {
                        HStack { ProgressView(); Text("Filialen zoeken…").foregroundStyle(.secondary) }
                    } else if branchSpots.isEmpty {
                        Text(stores.hasLocation
                             ? String(localized: "Geen filialen van \(WalletPass.storeName(card)) in de buurt gevonden.")
                             : String(localized: "Geef Pasr toegang tot je locatie om filialen in de buurt te vinden, of zet bij de kaart zelf een locatie vast."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(branchSpots) { row($0) }
                } header: {
                    Text("Filialen in de buurt")
                } footer: {
                    Text("\(chosen.count) van \(WalletPass.maxLocations) gekozen. iOS toont de pas op je toegangsscherm als je bij een van deze plekken bent; dat bepaalt iOS zelf.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(Brand.coral) }
                }
            }
            .navigationTitle("Wallet-pas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Maak pas") { Task { await make() } } }
                }
            }
            .task { await load() }
            .sheet(item: Binding(get: { pass.map(IdentifiedPass.init) }, set: { if $0 == nil { pass = nil } })) { item in
                AddPassSheet(pass: item.pass) { dismiss() }
                    .ignoresSafeArea()
            }
        }
    }

    private func row(_ spot: Spot) -> some View {
        Button {
            if chosen.contains(spot.id) { chosen.remove(spot.id) }
            else if chosen.count < WalletPass.maxLocations { chosen.insert(spot.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: chosen.contains(spot.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(chosen.contains(spot.id) ? Brand.iris : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.title).foregroundStyle(.primary)
                    if let detail = spot.detail { Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                if let here {
                    Text(NearbyPlacesView.distance(here.distance(from: CLLocation(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude))))
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!chosen.contains(spot.id) && chosen.count >= WalletPass.maxLocations)
    }

    private func load() async {
        defer { loading = false }
        chosen = Set(ownSpots.prefix(WalletPass.maxLocations).map(\.id))
        here = await stores.currentLocation(maxAge: 600)
        branches = await stores.branchesNearby(of: WalletPass.storeName(card))
        for spot in branchSpots where chosen.count < WalletPass.maxLocations { chosen.insert(spot.id) }
    }

    private func make() async {
        busy = true
        error = nil
        defer { busy = false }
        let all = ownSpots + branchSpots
        let picked = all.filter { chosen.contains($0.id) }.map(\.coordinate)
        do {
            pass = try await WalletPass.make(for: card, locations: picked)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct IdentifiedPass: Identifiable {
    let pass: PKPass
    var id: String { pass.serialNumber }
}

private struct WalletButton: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKAddPassButton, context: Context) { context.coordinator.action = action }
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

private struct AddPassSheet: UIViewControllerRepresentable {
    let pass: PKPass
    var onDone: () -> Void

    func makeUIViewController(context: Context) -> PKAddPassesViewController {
        let controller = PKAddPassesViewController(pass: pass) ?? PKAddPassesViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PKAddPassesViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
            controller.dismiss(animated: true)
            onDone()
        }
    }
}
