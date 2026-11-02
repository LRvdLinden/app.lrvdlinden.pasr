import SwiftUI
import PassKit
import CoreLocation
import MapKit

/// "Voeg toe aan Apple Wallet": the account server (function wallet-pass) turns the card into a signed Wallet
/// pass. The pass carries up to 10 nearby branches of the store, so iOS shows it on the lock screen there, like
/// any Wallet pass. Nothing is stored on the server.
enum WalletPass {
    static let passTypeID = "pass.nl.lrvdlinden.pasr"

    static var isAvailable: Bool { PKAddPassesViewController.canAddPasses() && AccountConfig.isConfigured }

    /// Already in Wallet? (Same serial number = the card's id.)
    static func isInWallet(_ card: Card) -> Bool {
        PKPassLibrary().pass(withPassTypeIdentifier: passTypeID, serialNumber: card.id.uuidString) != nil
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @MainActor
    static func make(for card: Card) async throws -> PKPass {
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
        let branches = await NearbyStores.shared.branchesNearby(of: StoreTemplates.template(id: card.templateID)?.name ?? card.storeName)
        if !branches.isEmpty {
            body["locations"] = branches.map { ["latitude": $0.latitude, "longitude": $0.longitude] }
        }

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

/// Apple's own "Add to Apple Wallet" button, then the system sheet to add the pass.
struct AddToWalletButton: View {
    let card: Card
    @State private var pass: PKPass?
    @State private var busy = false
    @State private var error: String?
    @State private var inWallet = false

    var body: some View {
        VStack(spacing: 8) {
            if inWallet {
                Label("Staat in Apple Wallet", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Brand.mint)
            } else {
                ZStack {
                    WalletButton { Task { await add() } }
                        .frame(height: 44)
                        .opacity(busy ? 0.4 : 1)
                        .disabled(busy)
                    if busy { ProgressView() }
                }
                .frame(maxWidth: 280)
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(Brand.coral).multilineTextAlignment(.center)
            }
        }
        .onAppear { inWallet = WalletPass.isInWallet(card) }
        .sheet(item: Binding(get: { pass.map(IdentifiedPass.init) }, set: { if $0 == nil { pass = nil } })) { item in
            AddPassSheet(pass: item.pass) { inWallet = WalletPass.isInWallet(card) }
                .ignoresSafeArea()
        }
    }

    private func add() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            pass = try await WalletPass.make(for: card)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Wallet-knop in het rijtje onder een kaart (zelfde glazen knop als de andere acties).
struct WalletActionButton: View {
    let card: Card
    @State private var pass: PKPass?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Button {
            Task { await add() }
        } label: {
            ZStack {
                Label("Voeg toe aan Apple Wallet", systemImage: "wallet.pass")
                    .labelStyle(.iconOnly)
                    .opacity(busy ? 0 : 1)
                if busy { ProgressView().controlSize(.small) }
            }
            .font(.title3)
            .frame(width: 30, height: 30)
        }
        .pasrGlassButton()
        .disabled(busy)
        .accessibilityLabel(Text("Voeg toe aan Apple Wallet"))
        .sheet(item: Binding(get: { pass.map(IdentifiedPass.init) }, set: { if $0 == nil { pass = nil } })) { item in
            AddPassSheet(pass: item.pass) {}
                .ignoresSafeArea()
        }
        .alert("Apple Wallet", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func add() async {
        busy = true
        defer { busy = false }
        do {
            pass = try await WalletPass.make(for: card)
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
