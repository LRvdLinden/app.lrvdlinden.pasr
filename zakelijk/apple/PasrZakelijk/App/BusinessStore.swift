import SwiftUI
import Observation

/// De zaken van de ingelogde gebruiker en welke er gekozen is (zaakkiezer bovenin).
@MainActor
@Observable
final class BusinessStore {
    static let shared = BusinessStore()

    private(set) var businesses: [Business] = []
    private(set) var loaded = false
    var loading = false
    var error: String?
    /// Uitnodigingscode uit een link (pasrzakelijk://uitnodiging#code of pasr.nl/zakelijk/uitnodiging/#code).
    var pendingInvite: String?

    private static let selectionKey = "business.selected"
    var selectedID: String = "" {
        didSet { UserDefaults.standard.set(selectedID, forKey: Self.selectionKey) }
    }

    private init() {
        selectedID = UserDefaults.standard.string(forKey: Self.selectionKey) ?? ""
    }

    var current: Business? {
        businesses.first { $0.id == selectedID } ?? businesses.first
    }

    func select(_ id: String) { selectedID = id }

    func load() async {
        guard Account.shared.isSignedIn else { return }
        loading = true
        defer { loading = false }
        do {
            businesses = try await BusinessAPI.me()
                .sorted { ($0.role == .owner ? 0 : 1, $0.name.lowercased()) < ($1.role == .owner ? 0 : 1, $1.name.lowercased()) }
            if !businesses.contains(where: { $0.id == selectedID }) { selectedID = businesses.first?.id ?? "" }
            error = nil
            // widgets (Vandaag, Komend event, Te doen) bijwerken, zonder het laden op te houden
            Task { await WidgetSync.refresh() }
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    func reset() {
        if !businesses.isEmpty { WidgetSync.clear() }
        businesses = []
        loaded = false
        error = nil
        selectedID = ""
    }

    /// Een link uit Safari, Berichten of de camera.
    /// Kent de app deze link zelf (uitnodiging voor medewerkers)?
    func handles(url: URL) -> Bool { Self.isInvite(url) || ZakelijkLink.parse(url) != nil }

    private static func isInvite(_ url: URL) -> Bool {
        (url.scheme == "pasrzakelijk" && (url.host() == "uitnodiging" || url.path().contains("uitnodiging")))
            || (url.host()?.hasSuffix("pasr.nl") == true && url.path().contains("/zakelijk/uitnodiging"))
    }

    func handle(url: URL) {
        // widget of melding: pasrzakelijk://open/<onderdeel>?zaak=<id>&id=<item>
        if let target = ZakelijkLink.parse(url) {
            if let id = target.business, businesses.isEmpty || businesses.contains(where: { $0.id == id }) { select(id) }
            if target.section == .gezamenlijkeActies, let campaign = target.item {
                CommunityRouter.shared.route(type: "community_invite", campaign: campaign)
            }
            AppNavigator.shared.request = target
            return
        }
        // uitnodiging voor een gezamenlijke actie: https://pasr.nl/zakelijk/uitnodiging/?t=TOKEN
        if Self.isInvite(url), let token = CommunityRouter.token(in: url) {
            CommunityRouter.shared.pendingToken = token
            return
        }
        if Self.isInvite(url) {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let code = url.fragment ?? items.first(where: { $0.name == "code" })?.value
            if let code = code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty, code.count <= 80 {
                pendingInvite = code
            }
        }
    }
}
