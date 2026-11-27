import SwiftUI

/// Gezamenlijke Pasr-winkelstraatacties. Meedoen kan alleen op uitnodiging van de organisator, of zelf als de actie
/// open staat voor zaken in dezelfde plaats.
/// Eigenaar: actie starten, zaken uitnodigen (zoeken, link of QR), uitnodigingen beantwoorden, uitstappen, stoppen
/// (alleen organisator) en uitgeven.
/// Medewerker: ziet alleen de acties waaraan de zaak meedoet en kan de beloning uitgeven
/// (bij het scannen verschijnt de beloning ook vanzelf, zie ScanResultSheet).
struct BusinessCommunityView: View {
    let business: Business
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var reward = ""
    @State private var required = 3
    @State private var days = 60
    @State private var openSameCity = false
    @State private var minParticipants = 2
    /// Lidcode per actie, zodat het typen in de ene actie de andere niet vult.
    @State private var memberCodes: [String: String] = [:]
    @State private var rows: [Campaign] = []
    @State private var invites: [MyInvite] = []
    @State private var loaded = false
    @State private var busy = false
    @State private var message: String?
    @State private var failed = false
    @State private var confirmCancel: Campaign?
    @State private var confirmLeave: Campaign?
    @State private var confirmDecline: MyInvite?
    @State private var managing: Campaign?
    @State private var scrollTarget: String?
    @State private var router = CommunityRouter.shared

    struct Campaign: Identifiable, Hashable {
        let id: String
        let name: String
        let reward: String
        let required: Int
        let participants: Int
        let participantNames: [String]
        let joined: Bool
        let isLead: Bool
        let lead: String
        let leadCity: String
        let endsAt: Date?
        let claimsHere: Int
        /// 'owner' (organisator) of 'participant'; leeg als de zaak (nog) niet meedoet.
        let role: String
        let openSameCity: Bool
        let minParticipants: Int
        let acceptedCount: Int
        let state: CommunityState

        init?(_ x: [String: Any]) {
            guard let j = JSONObject(x), let id = j.string("id", "campaign_id"), let name = j.string("name", "title") else { return nil }
            self.id = id; self.name = name
            reward = j.string("reward") ?? ""
            required = j.int("required") ?? 0
            participants = j.int("participants") ?? 0
            participantNames = (x["participant_names"] as? [Any])?.compactMap { $0 as? String } ?? []
            joined = j.bool("joined") ?? false
            isLead = j.bool("is_lead") ?? false
            lead = j.string("lead_business") ?? ""
            leadCity = j.string("lead_city") ?? ""
            endsAt = j.date("ends_at")
            claimsHere = j.int("claims_here") ?? 0
            // nieuwe velden tolerant lezen: een oudere server stuurt ze nog niet
            role = j.string("role") ?? (isLead ? "owner" : joined ? "participant" : "")
            openSameCity = j.bool("open_same_city") ?? false
            minParticipants = j.int("min_participants") ?? 0
            acceptedCount = j.int("accepted_count") ?? participants
            state = j.string("state").flatMap(CommunityState.init(rawValue:)) ?? .active
        }

        var isOrganizer: Bool { role == "owner" || isLead }
        var isParticipant: Bool { joined || role == "owner" || role == "participant" }

        var stateLabel: String {
            switch state {
            case .waiting: String(localized: "Wacht op \(acceptedCount) van \(max(minParticipants, acceptedCount)) zaken")
            case .active: String(localized: "Actief")
            case .ended: String(localized: "Afgelopen")
            case .cancelled: String(localized: "Gestopt")
            }
        }

        static func == (a: Campaign, b: Campaign) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }
    }

    struct MyInvite: Identifiable {
        let id: String
        let campaignID: String
        let title: String
        let reward: String
        let startsAt: Date?
        let endsAt: Date?
        let initiator: String
        let participants: [String]
        init?(_ any: Any) {
            guard let j = JSONObject(any), let id = j.string("invite_id", "id") else { return nil }
            self.id = id
            campaignID = j.string("campaign_id") ?? ""
            title = j.string("title", "name") ?? ""
            reward = j.string("reward") ?? ""
            startsAt = j.date("starts_at")
            endsAt = j.date("ends_at")
            initiator = j.string("initiator_name", "lead_business") ?? ""
            participants = (j.raw["participant_names"] as? [Any])?.compactMap { $0 as? String } ?? []
        }

        var period: String? {
            guard let end = endsAt else { return nil }
            let until = end.formatted(date: .abbreviated, time: .omitted)
            if let start = startsAt { return start.formatted(date: .abbreviated, time: .omitted) + " – " + until }
            return String(localized: "Loopt tot \(until)")
        }
    }

    private var isOwner: Bool { business.isOwner }
    private var nameOK: Bool { (3...80).contains(name.trimmingCharacters(in: .whitespacesAndNewlines).count) }
    private var rewardOK: Bool { (3...120).contains(reward.trimmingCharacters(in: .whitespacesAndNewlines).count) }

    var body: some View {
        dialogs(stack)
    }

    private var stack: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form { formContent }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation { proxy.scrollTo(target, anchor: .top) }
                    scrollTarget = nil
                }
            }
            .navigationTitle("Samenwerkingen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
            .navigationDestination(item: $managing) { campaign in
                CommunityInviteManagerView(business: business, campaign: campaign)
            }
            .task { await load(); await applyFocus() }
            .refreshable { await load() }
            .onChange(of: router.focus) { _, focus in
                guard focus != nil else { return }
                Task { await load(); await applyFocus() }
            }
            .onChange(of: managing) { _, now in if now == nil { Task { await load() } } }
        }
    }

    /// Bevestigingsvragen apart van de rest, zodat de compiler de body snel genoeg kan controleren.
    private func dialogs<V: View>(_ content: V) -> some View {
        content
            .busyWhile(confirmCancel != nil || confirmLeave != nil || confirmDecline != nil)
            .confirmationDialog("Actie stoppen?", isPresented: Binding(get: { confirmCancel != nil }, set: { if !$0 { confirmCancel = nil } }),
                                titleVisibility: .visible, presenting: confirmCancel) { row in
                Button("Actie stoppen", role: .destructive) { Task { await cancel(row.id) } }
                Button("Annuleren", role: .cancel) {}
            } message: { _ in
                Text("De actie verdwijnt bij klanten en alle deelnemende zaken. Uitgegeven beloningen blijven geregistreerd.")
            }
            .confirmationDialog("Uitstappen?", isPresented: Binding(get: { confirmLeave != nil }, set: { if !$0 { confirmLeave = nil } }),
                                titleVisibility: .visible, presenting: confirmLeave) { row in
                Button("Uitstappen", role: .destructive) { Task { await leave(row.id) } }
                Button("Annuleren", role: .cancel) {}
            } message: { _ in
                Text("Bezoeken bij jouw zaak tellen daarna niet meer mee voor klanten.")
            }
            .confirmationDialog("Uitnodiging weigeren?", isPresented: Binding(get: { confirmDecline != nil }, set: { if !$0 { confirmDecline = nil } }),
                                titleVisibility: .visible, presenting: confirmDecline) { invite in
                Button("Weigeren", role: .destructive) { Task { await respond(invite, accept: false) } }
                Button("Annuleren", role: .cancel) {}
            } message: { _ in
                Text("De organisator ziet dat je zaak niet meedoet.")
            }
    }

    @ViewBuilder private var formContent: some View {
        invitesSection
        createSection
        campaignsSection
        messageSection
    }

    @ViewBuilder private var invitesSection: some View {
        if isOwner && !invites.isEmpty {
            Section {
                ForEach(invites) { invite in inviteRow(invite) }
            } header: {
                Text("Uitnodigingen (\(invites.count))")
            } footer: {
                Text("Je beslist zelf of je zaak meedoet. Klantgegevens worden niet tussen ondernemingen gedeeld.")
            }
            .id("invites")
        }
    }

    @ViewBuilder private var createSection: some View {
        if isOwner {
            Section {
                TextField("Actienaam", text: $name)
                TextField("Gezamenlijke beloning", text: $reward)
                Stepper("Benodigde verschillende winkels: \(required)", value: $required, in: 2...20)
                Stepper("Looptijd: \(days) dagen", value: $days, in: 1...366)
                Toggle("Open voor zaken in dezelfde plaats", isOn: $openSameCity)
                Stepper("Minimum aantal zaken: \(minParticipants)", value: $minParticipants, in: 2...20)
                Button("Samenwerking starten") { Task { await create() } }
                    .disabled(busy || !nameOK || !rewardOK)
            } header: {
                Text("Nieuwe gezamenlijke actie")
            } footer: {
                Text("Je nodigt zelf zaken uit; zij beslissen of ze meedoen. De actie start voor klanten zodra het minimum aantal zaken meedoet. Klanten verzamelen een bezoek met een stempel bij elke deelnemende zaak. Klantgegevens worden niet tussen ondernemingen gedeeld.")
            }
        }
    }

    @ViewBuilder private var campaignsSection: some View {
        Section {
            if !loaded && rows.isEmpty {
                ProgressView()
            } else if rows.isEmpty {
                (isOwner ? Text("Nog geen gezamenlijke acties") : Text("Je zaak doet nog niet mee aan een gezamenlijke actie"))
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { row in campaignRow(row).id(row.id) }
        } header: {
            isOwner ? Text("Gezamenlijke acties") : Text("Acties van je zaak")
        } footer: {
            Text("Bij het scannen van een klant zie je vanzelf of die een gezamenlijke beloning heeft verdiend.")
        }
    }

    @ViewBuilder private var messageSection: some View {
        if let message {
            Section {
                Label(message, systemImage: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(failed ? Theme.coral : Theme.mint)
            }
            .id("message")
        }
    }

    @ViewBuilder private func inviteRow(_ invite: MyInvite) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: invite.title).font(.headline)
            if !invite.reward.isEmpty { Text("Beloning: \(invite.reward)") }
            if let period = invite.period { Text(verbatim: period).font(.caption).foregroundStyle(.secondary) }
            if !invite.initiator.isEmpty {
                Text("Organisator: \(invite.initiator)").font(.caption).foregroundStyle(.secondary)
            }
            if !invite.participants.isEmpty {
                Text("Doen mee: \(invite.participants.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Accepteren") { Task { await respond(invite, accept: true) } }
                    .buttonStyle(.borderedProminent)
                Button("Weigeren", role: .destructive) { confirmDecline = invite }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
            .disabled(busy)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func campaignRow(_ row: Campaign) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: row.name).font(.headline)
                Spacer()
                if row.isOrganizer {
                    Text("Organisator").font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.mint.opacity(0.18), in: Capsule())
                }
            }
            StatusCapsule(text: row.stateLabel, color: row.state.color)
            let leadLine: String = [row.lead, row.leadCity].filter { !$0.isEmpty }.joined(separator: ", ")
            let countLine: String = String(localized: "\(row.participants) deelnemende zaken")
            Text(verbatim: leadLine.isEmpty ? countLine : leadLine + " · " + countLine)
                .font(.caption).foregroundStyle(.secondary)
            if !row.participantNames.isEmpty {
                Text(verbatim: row.participantNames.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Beloning: \(row.reward)")
            Text("Bezoek \(row.required) verschillende deelnemende winkels")
                .font(.caption).foregroundStyle(.secondary)
            if let end = row.endsAt {
                Text("Loopt tot \(end.formatted(date: .long, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if row.openSameCity {
                Label("Open voor zaken in dezelfde plaats", systemImage: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isOwner && row.isOrganizer && (row.state == .waiting || row.state == .active) {
                Button("Zaken uitnodigen", systemImage: "person.badge.plus") { managing = row }
                    .disabled(busy)
            }
            if !row.isParticipant {
                if isOwner && row.openSameCity && (row.state == .waiting || row.state == .active) {
                    Button("Meedoen (open voor zaken in jouw plaats)") { Task { await join(row.id) } }
                        .disabled(busy)
                } else {
                    Text("Meedoen kan alleen op uitnodiging van de organisator.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Label(row.claimsHere > 0 ? String(localized: "Je onderneming neemt deel · \(row.claimsHere)x uitgegeven") : String(localized: "Je onderneming neemt deel"),
                      systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
                if row.state == .active {
                    TextField("Lidcode bij de kassa (PZ…)", text: Binding(
                        get: { memberCodes[row.id] ?? "" },
                        set: { memberCodes[row.id] = $0 }))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Gezamenlijke beloning controleren en uitgeven") {
                        Task { await claim(row.id) }
                    }
                    .disabled(busy || !(memberCodes[row.id] ?? "").trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("PZ"))
                }
                if isOwner && (row.state == .waiting || row.state == .active) {
                    if row.isOrganizer {
                        Button("Actie stoppen", role: .destructive) { confirmCancel = row }.disabled(busy)
                    } else {
                        Button("Uitstappen", role: .destructive) { confirmLeave = row }.disabled(busy)
                    }
                }
            }
        }
        .buttonStyle(.borderless)
    }

    private func show(_ text: String, error: Bool = false) {
        message = text; failed = error
    }

    /// Melding of geaccepteerde link: naar de juiste plek springen.
    @MainActor private func applyFocus() {
        guard loaded, let focus = router.focus else { return }
        router.focus = nil
        if let notice = focus.notice { show(notice, error: focus.failed) }
        switch focus.kind {
        case "community_invite":
            scrollTarget = invites.isEmpty ? focus.campaign : "invites"
        case "community_invite_answered":
            if isOwner, let id = focus.campaign, let row = rows.first(where: { $0.id == id }), row.isOrganizer {
                managing = row
            } else {
                scrollTarget = focus.campaign
            }
        case "community_removed":
            show(String(localized: "Je zaak doet niet meer mee aan deze gezamenlijke actie."))
            scrollTarget = "message"
        default:
            scrollTarget = focus.notice != nil ? "message" : focus.campaign
        }
    }

    @MainActor private func load() async {
        do {
            let r = try await Account.shared.rpc("pasr_business_community_list", ["p_business": business.id])
            rows = (r as? [[String: Any]] ?? []).compactMap(Campaign.init)
        } catch { show(error.localizedDescription, error: true) }
        if isOwner {
            // een oudere server kent deze functie nog niet: dan gewoon geen uitnodigingen
            if let r = try? await Account.shared.rpc("pasr_business_community_my_invites", ["p_business": business.id]) {
                invites = (r as? [Any] ?? []).compactMap(MyInvite.init)
            }
            router.inviteCount = invites.count
        }
        loaded = true
    }

    @MainActor private func create() async {
        busy = true; defer { busy = false }
        var args: [String: Any] = [
            "p_business": business.id,
            "p_name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "p_reward": reward.trimmingCharacters(in: .whitespacesAndNewlines),
            "p_required": required, "p_days": days
        ]
        args["p_open_same_city"] = openSameCity
        args["p_min_participants"] = minParticipants
        do {
            let r = try await Account.shared.rpc("pasr_business_community_create", args)
            let newID = JSONObject(r)?.string("campaign_id", "id")
            name = ""; reward = ""; openSameCity = false; minParticipants = 2
            show(String(localized: "Samenwerking gestart. Nodig nu zaken uit om mee te doen."))
            await load()
            if let newID, let row = rows.first(where: { $0.id == newID }) { managing = row }
        } catch { show(error.localizedDescription, error: true) }
    }
    @MainActor private func respond(_ invite: MyInvite, accept: Bool) async {
        busy = true; defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_respond",
                ["p_business": business.id, "p_invite": invite.id, "p_accept": accept])
            show(accept ? String(localized: "Je onderneming doet nu mee aan \(invite.title).")
                        : String(localized: "Uitnodiging geweigerd."))
            await load()
            if accept, !invite.campaignID.isEmpty { scrollTarget = invite.campaignID }
        } catch { show(error.localizedDescription, error: true) }
    }
    @MainActor private func join(_ id: String) async {
        busy = true; defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_join",
                ["p_business": business.id, "p_campaign": id])
            show(String(localized: "Je onderneming neemt nu deel."))
            await load()
        } catch { show(error.localizedDescription, error: true) }
    }
    @MainActor private func leave(_ id: String) async {
        busy = true; defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_leave",
                ["p_business": business.id, "p_campaign": id])
            show(String(localized: "Je onderneming doet niet meer mee aan deze actie."))
            await load()
        } catch { show(error.localizedDescription, error: true) }
    }
    @MainActor private func cancel(_ id: String) async {
        busy = true; defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_cancel",
                ["p_business": business.id, "p_campaign": id])
            show(String(localized: "De actie is gestopt."))
            await load()
        } catch { show(error.localizedDescription, error: true) }
    }
    @MainActor private func claim(_ id: String) async {
        busy = true; defer { busy = false }
        do {
            let r = try await Account.shared.rpc("pasr_business_community_claim", [
                "p_business": business.id, "p_campaign": id,
                "p_member_code": (memberCodes[id] ?? "").uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            ])
            let reward = JSONObject(r)?.string("reward") ?? String(localized: "gezamenlijke beloning")
            show(String(localized: "Beloning uitgegeven: \(reward). Een tweede inwisseling is niet mogelijk."))
            memberCodes[id] = nil
            await load()
        } catch { show(error.localizedDescription, error: true) }
    }
}
