import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Uitnodigingen voor gezamenlijke acties: wat er vanuit een melding of link geopend moet worden, en hoeveel
/// openstaande uitnodigingen de zaak heeft (badge bij Acties en Samenwerkingen).
@MainActor
@Observable
final class CommunityRouter {
    static let shared = CommunityRouter()

    /// Pushtypes die naar Samenwerkingen gaan (payload `type` met `campaign`).
    nonisolated static let pushTypes: Set<String> = ["community_invite", "community_invite_answered", "community_active", "community_removed"]

    struct Focus: Equatable {
        let kind: String
        let campaign: String?
        var notice: String?
        var failed = false
        let stamp = UUID()
    }

    /// Wat Samenwerkingen moet openen (melding of geaccepteerde link).
    var focus: Focus?
    /// Token uit https://pasr.nl/zakelijk/uitnodiging/?t=TOKEN (nog niet bevestigd).
    var pendingToken: String?
    /// Openstaande uitnodigingen voor de gekozen zaak.
    var inviteCount = 0

    func route(type: String, campaign: String?) {
        guard Self.pushTypes.contains(type) else { return }
        focus = Focus(kind: type, campaign: campaign?.isEmpty == true ? nil : campaign)
    }

    func refreshCount(business: Business) async {
        guard business.isOwner else { inviteCount = 0; return }
        guard let result = try? await Account.shared.rpc("pasr_business_community_my_invites", ["p_business": business.id]) else { return }
        inviteCount = (result as? [Any])?.count ?? 0
    }

    /// Token uit een uitnodigingslink, of nil als dit geen link voor een gezamenlijke actie is.
    nonisolated static func token(in url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let t = items.first(where: { $0.name == "t" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty, t.count <= 200 else { return nil }
        return t
    }
}

/// Status van een gezamenlijke actie ('waiting' | 'active' | 'ended' | 'cancelled').
enum CommunityState: String {
    case waiting, active, ended, cancelled

    var color: Color {
        switch self {
        case .waiting: Theme.amber
        case .active: Theme.mint
        case .ended: Theme.muted
        case .cancelled: Theme.coral
        }
    }
}

/// Status van één uitnodiging ('invited' | 'accepted' | 'declined' | 'revoked').
enum CommunityInviteStatus: String {
    case invited, accepted, declined, revoked

    var label: String {
        switch self {
        case .invited: String(localized: "Uitgenodigd")
        case .accepted: String(localized: "Doet mee")
        case .declined: String(localized: "Geweigerd")
        case .revoked: String(localized: "Ingetrokken")
        }
    }

    var color: Color {
        switch self {
        case .invited: Theme.sky
        case .accepted: Theme.mint
        case .declined: Theme.coral
        case .revoked: Theme.muted
        }
    }
}

struct StatusCapsule: View {
    let text: String
    let color: Color
    var body: some View {
        Text(verbatim: text).font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Organisator: zaken zoeken en uitnodigen, uitnodigen via link of QR, en de status per zaak (intrekken, verwijderen).
struct CommunityInviteManagerView: View {
    let business: Business
    let campaign: BusinessCommunityView.Campaign

    struct Found: Identifiable {
        let id: String
        let name: String
        let city: String
        let logo: String?
        var status: CommunityInviteStatus?
        init?(_ any: Any) {
            guard let j = JSONObject(any), let id = j.string("business_id", "id") else { return nil }
            self.id = id
            name = j.string("name") ?? ""
            city = j.string("city") ?? ""
            logo = j.string("logo_url", "logo")
            status = j.string("invite_status").flatMap(CommunityInviteStatus.init(rawValue:))
        }
    }

    struct Invite: Identifiable {
        let id: String
        let businessID: String?
        let name: String
        let city: String
        let email: String?
        let status: CommunityInviteStatus
        let createdAt: Date?
        init?(_ any: Any) {
            guard let j = JSONObject(any), let id = j.string("invite_id", "id") else { return nil }
            self.id = id
            businessID = j.string("business_id")
            name = j.string("name") ?? ""
            city = j.string("city") ?? ""
            email = j.string("email")
            status = j.string("status").flatMap(CommunityInviteStatus.init(rawValue:)) ?? .invited
            createdAt = j.date("created_at")
        }
        var title: String { name.isEmpty ? (email ?? "") : name }
    }

    struct InviteLink: Equatable {
        let link: String
        let email: String?
    }

    @State private var query = ""
    @State private var results: [Found] = []
    @State private var searching = false
    @State private var invites: [Invite] = []
    @State private var loaded = false
    @State private var email = ""
    @State private var link: InviteLink?
    @State private var busy = false
    @State private var message: String?
    @State private var failed = false
    @State private var confirmRevoke: Invite?
    @State private var confirmRemove: Invite?

    private var emailOK: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty || e.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(verbatim: campaign.name).font(.headline)
                    Spacer()
                    StatusCapsule(text: campaign.stateLabel, color: campaign.state.color)
                }
                if campaign.state == .waiting {
                    Text("De actie start zodra genoeg zaken meedoen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                TextField("Zoek op naam of plaats", text: $query)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if searching { ProgressView() }
                ForEach(results) { result in searchRow(result) }
                if !searching && results.isEmpty && query.trimmingCharacters(in: .whitespaces).count >= 2 {
                    Text("Geen zaken gevonden").foregroundStyle(.secondary)
                }
            } header: {
                Text("Zaken zoeken")
            } footer: {
                Text("De zaak krijgt een melding en beslist zelf of zij meedoet.")
            }

            Section {
                TextField("E-mailadres (optioneel)", text: $email)
                    .keyboard(.email)
                    .textContentType(.emailAddress)
                    .capitalization(.never)
                    .autocorrectionDisabled()
                Button("Uitnodigingslink maken", systemImage: "link") { Task { await makeLink() } }
                    .disabled(busy || !emailOK)
                if let link { linkView(link) }
            } header: {
                Text("Uitnodigen via link of QR")
            } footer: {
                Text("Voor zaken die je niet kunt vinden of die Pasr Zakelijk nog niet gebruiken. Met een e-mailadres stuurt Pasr de uitnodiging ook per mail.")
            }

            Section {
                if !loaded && invites.isEmpty {
                    ProgressView()
                } else if invites.isEmpty {
                    Text("Nog niemand uitgenodigd").foregroundStyle(.secondary)
                }
                ForEach(invites) { invite in inviteRow(invite) }
            } header: {
                Text("Status per zaak")
            }

            if let message {
                Section {
                    Label(message, systemImage: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(failed ? Theme.coral : Theme.mint)
                }
            }
        }
        .navigationTitle("Zaken uitnodigen")
        .inlineTitle()
        .task { await loadInvites() }
        .refreshable { await loadInvites() }
        .macRefreshButton { await loadInvites() }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await search()
        }
        .busyWhile(confirmRevoke != nil || confirmRemove != nil)
        .confirmationDialog("Uitnodiging intrekken?", isPresented: Binding(get: { confirmRevoke != nil }, set: { if !$0 { confirmRevoke = nil } }),
                            titleVisibility: .visible, presenting: confirmRevoke) { invite in
            Button("Intrekken", role: .destructive) { Task { await revoke(invite) } }
            Button("Annuleren", role: .cancel) {}
        } message: { _ in
            Text("De uitnodiging en de link werken daarna niet meer.")
        }
        .confirmationDialog("Zaak verwijderen uit de actie?", isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
                            titleVisibility: .visible, presenting: confirmRemove) { invite in
            Button("Verwijderen", role: .destructive) { Task { await remove(invite) } }
            Button("Annuleren", role: .cancel) {}
        } message: { _ in
            Text("Bezoeken bij deze zaak tellen daarna niet meer mee voor klanten. De zaak krijgt hiervan een melding.")
        }
    }

    @ViewBuilder private func searchRow(_ result: Found) -> some View {
        HStack(spacing: 12) {
            CommunityLogo(source: result.logo)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: result.name).font(.subheadline.weight(.semibold))
                if !result.city.isEmpty { Text(verbatim: result.city).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if let status = result.status, status == .invited || status == .accepted {
                StatusCapsule(text: status.label, color: status.color)
            } else {
                Button("Uitnodigen") { Task { await invite(result) } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(busy)
            }
        }
    }

    @ViewBuilder private func linkView(_ link: InviteLink) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let email = link.email {
                Label(String(localized: "Uitnodiging verstuurd naar \(email)"), systemImage: "envelope.fill")
                    .font(.caption).foregroundStyle(Theme.mint)
            }
            Text(verbatim: link.link)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
            if let qr = QRCode.image(link.link) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text("QR-code van de uitnodigingslink"))
            }
            HStack {
                if let url = URL(string: link.link) {
                    ShareLink(item: url, subject: Text(verbatim: campaign.name),
                              message: Text("Doe mee met onze gezamenlijke Pasr-actie \"\(campaign.name)\".")) {
                        Label("Delen", systemImage: "square.and.arrow.up")
                    }
                }
                Spacer()
                Button("Kopiëren", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = link.link
                    show(String(localized: "Link gekopieerd."))
                }
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder private func inviteRow(_ invite: Invite) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: invite.title.isEmpty ? String(localized: "Uitnodigingslink") : invite.title)
                        .font(.subheadline.weight(.semibold))
                    let sub = [invite.city, invite.createdAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    if !sub.isEmpty { Text(verbatim: sub).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                StatusCapsule(text: invite.status.label, color: invite.status.color)
            }
            if invite.status == .invited {
                Button("Intrekken", role: .destructive) { confirmRevoke = invite }.disabled(busy)
            } else if invite.status == .accepted, let target = invite.businessID, target != business.id {
                Button("Verwijderen uit actie", role: .destructive) { confirmRemove = invite }.disabled(busy)
            }
        }
        .buttonStyle(.borderless)
    }

    private func show(_ text: String, error: Bool = false) { message = text; failed = error }

    @MainActor private func loadInvites() async {
        do {
            let r = try await Account.shared.rpc("pasr_business_community_invites",
                                                 ["p_business": business.id, "p_campaign": campaign.id])
            invites = (r as? [Any] ?? []).compactMap(Invite.init)
        } catch { show(error.localizedDescription, error: true) }
        loaded = true
    }

    @MainActor private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { results = []; return }
        searching = true; defer { searching = false }
        do {
            let r = try await Account.shared.rpc("pasr_business_community_search",
                                                 ["p_business": business.id, "p_campaign": campaign.id, "p_query": q])
            guard q == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            results = (r as? [Any] ?? []).compactMap(Found.init).filter { $0.id != business.id }
        } catch { show(error.localizedDescription, error: true) }
    }

    @MainActor private func invite(_ result: Found) async {
        busy = true; defer { busy = false }
        do {
            let r = try await Account.shared.rpc("pasr_business_community_invite",
                                                 ["p_business": business.id, "p_campaign": campaign.id, "p_target": result.id])
            let status = JSONObject(r)?.string("status").flatMap(CommunityInviteStatus.init(rawValue:)) ?? .invited
            if let i = results.firstIndex(where: { $0.id == result.id }) { results[i].status = status }
            show(String(localized: "\(result.name) is uitgenodigd."))
            await loadInvites()
        } catch { show(error.localizedDescription, error: true) }
    }

    @MainActor private func makeLink() async {
        busy = true; defer { busy = false }
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            let r = try await Account.shared.rpc("pasr_business_community_invite_email", [
                "p_business": business.id, "p_campaign": campaign.id,
                "p_email": mail.isEmpty ? NSNull() as Any : mail as Any
            ])
            let j = JSONObject(r)
            let token = j?.string("token") ?? ""
            let url = j?.string("link") ?? (token.isEmpty ? "" : "https://pasr.nl/zakelijk/uitnodiging/?t=\(token)")
            guard !url.isEmpty else { throw APIError(String(localized: "Er ging iets mis. Probeer het opnieuw.")) }
            link = InviteLink(link: url, email: mail.isEmpty ? nil : mail)
            email = ""
            message = nil
            await loadInvites()
        } catch { show(error.localizedDescription, error: true) }
    }

    @MainActor private func revoke(_ invite: Invite) async {
        busy = true; defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_revoke", ["p_business": business.id, "p_invite": invite.id])
            show(String(localized: "Uitnodiging ingetrokken."))
            await loadInvites()
            await search()
        } catch { show(error.localizedDescription, error: true) }
    }

    @MainActor private func remove(_ invite: Invite) async {
        guard let target = invite.businessID else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_remove",
                                             ["p_business": business.id, "p_campaign": campaign.id, "p_target": target])
            show(String(localized: "Zaak verwijderd uit de actie."))
            await loadInvites()
        } catch { show(error.localizedDescription, error: true) }
    }
}

/// Logo van een zaak in de zoekresultaten: https-URL of data-URL (base64), anders een neutraal icoon.
struct CommunityLogo: View {
    let source: String?

    var body: some View {
        Group {
            if let source, !source.lowercased().hasPrefix("http"),
               let data = Data(base64Encoded: String(source.split(separator: ",").last ?? ""), options: .ignoreUnknownCharacters),
               let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let source, source.lowercased().hasPrefix("https://"), let url = URL(string: source) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Theme.card2
            Image(systemName: "storefront").foregroundStyle(.secondary)
        }
    }
}
