import SwiftUI

// MARK: - Gezamenlijke actie: uitnodigingen en deelnemers (community_detail / _revoke / _remove), zoals beheer.pasr.nl

struct CommunityDetail: Decodable {
    struct Campaign: Decodable {
        let id: String; let name: String; let reward: String
        let starts_at: String?; let ends_at: String?; let cancelled_at: String?
        let open_same_city: Bool?; let min_participants: Int?; let accepted_count: Int?; let state: String?
        let lead_business: String?; let claims: Int?
    }
    struct Participant: Decodable, Identifiable {
        let business_id: String; let name: String; let city: String?; let accepted_at: String?; let organizer: Bool?
        var id: String { business_id }
    }
    struct Invite: Decodable, Identifiable {
        let invite_id: String; let business_id: String?; let name: String; let city: String?; let email: String?
        let status: String; let created_at: String?; let expires_at: String?; let organizer: Bool?; let link: Bool?
        var id: String { invite_id }
    }
    let campaign: Campaign
    let participants: [Participant]
    let invites: [Invite]
}

struct CommunityCampaignView: View {
    let campaignID: String
    let title: String
    var onChanged: () -> Void = {}
    @EnvironmentObject private var session: Session
    @State private var detail: CommunityDetail?
    @State private var error: String?
    @State private var removing: CommunityDetail.Participant?
    @State private var revoking: CommunityDetail.Invite?

    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return Self.iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    private func day(_ s: String?) -> String { date(s)?.formatted(date: .abbreviated, time: .omitted) ?? "—" }
    private func stateText(_ s: String?) -> String {
        switch s {
        case "waiting": return String(localized: "Wacht op deelnemers")
        case "active": return String(localized: "Actief")
        case "ended": return String(localized: "Afgelopen")
        case "cancelled": return String(localized: "Gestopt")
        default: return s ?? "—"
        }
    }
    private func statusText(_ i: CommunityDetail.Invite) -> String {
        if i.status == "invited", let e = date(i.expires_at), e < .now { return String(localized: "Verlopen") }
        switch i.status {
        case "invited": return String(localized: "Uitgenodigd")
        case "accepted": return String(localized: "Doet mee")
        case "declined": return String(localized: "Geweigerd")
        case "revoked": return String(localized: "Ingetrokken")
        default: return i.status
        }
    }
    private var live: Bool { detail?.campaign.state == "waiting" || detail?.campaign.state == "active" }

    var body: some View {
        Form {
            if let error { Text(error).foregroundStyle(.red) }
            if let d = detail {
                Section {
                    LabeledContent("Status", value: stateText(d.campaign.state))
                    LabeledContent("Deelnemers", value: String(localized: "\(d.campaign.accepted_count ?? 0) van minimaal \(d.campaign.min_participants ?? 2)"))
                    LabeledContent("Meedoen", value: d.campaign.open_same_city == true ? String(localized: "Open voor dezelfde plaats") : String(localized: "Alleen op uitnodiging"))
                    LabeledContent("Looptijd", value: "\(day(d.campaign.starts_at)) – \(day(d.campaign.ends_at))")
                    LabeledContent("Beloningen uitgegeven", value: "\(d.campaign.claims ?? 0)")
                } header: { Text(d.campaign.reward) }
                Section {
                    ForEach(d.participants) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name + (p.city.map { $0.isEmpty ? "" : " · \($0)" } ?? "")).font(.subheadline.weight(.semibold))
                                Text((p.organizer == true ? String(localized: "Organisator") + " · " : "") + String(localized: "sinds \(day(p.accepted_at))"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if live && p.organizer != true {
                                Button("Verwijderen", role: .destructive) { removing = p }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                } header: { Text("Deelnemers") }
                Section {
                    let invites = d.invites.filter { $0.organizer != true }
                    if invites.isEmpty { Text("Nog geen uitnodigingen.").foregroundStyle(.secondary) }
                    ForEach(invites) { i in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(i.name + (i.city.map { $0.isEmpty ? "" : " · \($0)" } ?? "") + (i.link == true && i.business_id == nil ? " (link)" : ""))
                                    .font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text("\(statusText(i)) · \(day(i.created_at))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if live && i.status == "invited" && (date(i.expires_at) ?? .distantFuture) > .now {
                                Button("Intrekken", role: .destructive) { revoking = i }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                } header: { Text("Uitnodigingen") }
            } else if error == nil {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle(title)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(String(localized: "Deelnemer verwijderen?"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Verwijderen", role: .destructive) {
                if let p = removing { Task { await remove(p) } }
            }
        } message: {
            Text("\(removing?.name ?? "") doet daarna niet meer mee. De zaak krijgt een mail en een melding.")
        }
        .confirmationDialog(String(localized: "Uitnodiging intrekken?"), isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible) {
            Button("Intrekken", role: .destructive) {
                if let i = revoking { Task { await revoke(i) } }
            }
        } message: {
            Text("De uitnodiging vervalt. De ontvanger krijgt een mail.")
        }
    }

    private func load() async {
        do { detail = try await session.call("community_detail", ["id": campaignID], as: CommunityDetail.self); error = nil }
        catch is CancellationError {}
        catch { self.error = error.localizedDescription }
    }

    private func remove(_ p: CommunityDetail.Participant) async {
        do { try await session.call("community_remove", ["campaign_id": campaignID, "business_id": p.business_id]); await load(); onChanged() }
        catch { self.error = error.localizedDescription }
    }

    private func revoke(_ i: CommunityDetail.Invite) async {
        do { try await session.call("community_revoke", ["invite_id": i.invite_id]); await load() }
        catch { self.error = error.localizedDescription }
    }
}
