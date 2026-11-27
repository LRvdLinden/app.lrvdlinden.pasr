import SwiftUI

// Gezamenlijke acties op de Mac: een actie in de lijst is aanklikbaar en opent deze detailweergave met dezelfde
// mogelijkheden als de knoppen in de rij op iOS (zaken uitnodigen, status per zaak, meedoen, beloning uitgeven,
// stoppen of uitstappen). De logica (RPC's, bevestigingsvragen) blijft in BusinessCommunityView.

/// Wat de detailweergave aan BusinessCommunityView vraagt.
struct CommunityActions {
    let join: (String) -> Void
    let claim: (String) -> Void
    let stop: (BusinessCommunityView.Campaign) -> Void
    let leave: (BusinessCommunityView.Campaign) -> Void
    let reload: @MainActor () async -> Void
}

/// Koppelt de detailweergave aan de navigatie van Samenwerkingen (alleen op de Mac; op iOS doet dit niets).
struct CommunityDetailDestination: ViewModifier {
    let business: Business
    @Binding var opened: BusinessCommunityView.Campaign?
    @Binding var rows: [BusinessCommunityView.Campaign]
    @Binding var memberCodes: [String: String]
    @Binding var busy: Bool
    @Binding var message: String?
    @Binding var failed: Bool
    let actions: CommunityActions

    func body(content: Content) -> some View {
        #if os(macOS)
        content.navigationDestination(item: $opened) { campaign in
            CommunityCampaignDetail(business: business, campaignID: campaign.id, rows: $rows, memberCodes: $memberCodes,
                                    busy: $busy, message: $message, failed: $failed, actions: actions)
        }
        #else
        content
        #endif
    }
}

/// Korte samenvatting van een actie (rij in de lijst en kop van de detailweergave).
struct CommunityCampaignSummary: View {
    let campaign: BusinessCommunityView.Campaign

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: campaign.name).font(.headline)
                StatusCapsule(text: campaign.stateLabel, color: campaign.state.color)
                Spacer(minLength: 4)
                if campaign.isOrganizer {
                    Text("Organisator").font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.mint.opacity(0.18), in: Capsule())
                }
            }
            Text("Beloning: \(campaign.reward)").font(.subheadline)
            Text(verbatim: line).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var line: String {
        var parts: [String] = []
        let lead = [campaign.lead, campaign.leadCity].filter { !$0.isEmpty }.joined(separator: ", ")
        if !lead.isEmpty { parts.append(lead) }
        parts.append(String(localized: "\(campaign.participants) deelnemende zaken"))
        if let end = campaign.endsAt {
            parts.append(String(localized: "Loopt tot \(end.formatted(date: .long, time: .omitted))"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Detailweergave van één gezamenlijke actie (Mac).
struct CommunityCampaignDetail: View {
    let business: Business
    let campaignID: String
    @Binding var rows: [BusinessCommunityView.Campaign]
    @Binding var memberCodes: [String: String]
    @Binding var busy: Bool
    @Binding var message: String?
    @Binding var failed: Bool
    let actions: CommunityActions

    private var campaign: BusinessCommunityView.Campaign? { rows.first { $0.id == campaignID } }

    var body: some View {
        Group {
            if let campaign {
                Form {
                    infoSection(campaign)
                    participationSection(campaign)
                    if business.isOwner && campaign.isOrganizer { organizerSection(campaign) }
                    endSection(campaign)
                    if let message {
                        Section {
                            Label(message, systemImage: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(failed ? Theme.coral : Theme.mint)
                        }
                    }
                }
                .navigationTitle(Text(verbatim: campaign.name))
            } else {
                ContentUnavailableView("Deze actie bestaat niet meer", systemImage: "person.3")
            }
        }
        .macRefreshButton { await actions.reload() }
    }

    private func isRunning(_ c: BusinessCommunityView.Campaign) -> Bool { c.state == .waiting || c.state == .active }

    @ViewBuilder private func infoSection(_ c: BusinessCommunityView.Campaign) -> some View {
        Section {
            CommunityCampaignSummary(campaign: c)
            LabeledContent("Voorwaarde") { Text("Bezoek \(c.required) verschillende deelnemende winkels") }
            if c.minParticipants > 0 {
                LabeledContent("Minimum aantal zaken") { Text(verbatim: "\(c.minParticipants)").monospacedDigit() }
            }
            if !c.participantNames.isEmpty {
                LabeledContent("Doen mee") { Text(verbatim: c.participantNames.joined(separator: ", ")).multilineTextAlignment(.trailing) }
            }
            if c.openSameCity {
                Label("Open voor zaken in dezelfde plaats", systemImage: "mappin.and.ellipse")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if c.state == .waiting {
                Text("De actie start zodra genoeg zaken meedoen.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func participationSection(_ c: BusinessCommunityView.Campaign) -> some View {
        Section {
            if !c.isParticipant {
                if business.isOwner && c.openSameCity && isRunning(c) {
                    Button("Meedoen (open voor zaken in jouw plaats)", systemImage: "person.crop.circle.badge.checkmark") { actions.join(c.id) }
                        .disabled(busy)
                } else {
                    Text("Meedoen kan alleen op uitnodiging van de organisator.").foregroundStyle(.secondary)
                }
            } else {
                Label(c.claimsHere > 0 ? String(localized: "Je onderneming neemt deel · \(c.claimsHere)x uitgegeven")
                                       : String(localized: "Je onderneming neemt deel"),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if c.state == .active {
                    TextField("Lidcode bij de kassa (PZ…)", text: Binding(
                        get: { memberCodes[c.id] ?? "" },
                        set: { memberCodes[c.id] = $0 }))
                        .autocorrectionDisabled()
                        .onSubmit { if codeOK(c) { actions.claim(c.id) } }
                    Button("Gezamenlijke beloning controleren en uitgeven", systemImage: "gift") { actions.claim(c.id) }
                        .disabled(busy || !codeOK(c))
                }
            }
        } header: {
            Text("Jouw zaak")
        } footer: {
            Text("Bij het scannen van een klant zie je vanzelf of die een gezamenlijke beloning heeft verdiend.")
        }
    }

    @ViewBuilder private func organizerSection(_ c: BusinessCommunityView.Campaign) -> some View {
        Section {
            if isRunning(c) {
                NavigationLink {
                    CommunityInviteManagerView(business: business, campaign: c)
                } label: {
                    Label("Zaken uitnodigen en status per zaak", systemImage: "person.badge.plus")
                }
            } else {
                Text("Deze actie loopt niet meer; uitnodigen kan niet meer.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Organisator")
        } footer: {
            Text("Zaken zoeken en uitnodigen, uitnodigen via link of QR, en per zaak de status: uitnodiging intrekken of een zaak uit de actie verwijderen.")
        }
    }

    @ViewBuilder private func endSection(_ c: BusinessCommunityView.Campaign) -> some View {
        if business.isOwner && c.isParticipant && isRunning(c) {
            Section {
                if c.isOrganizer {
                    Button("Actie stoppen", systemImage: "stop.circle", role: .destructive) { actions.stop(c) }
                        .disabled(busy)
                } else {
                    Button("Uitstappen", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { actions.leave(c) }
                        .disabled(busy)
                }
            }
        }
    }

    private func codeOK(_ c: BusinessCommunityView.Campaign) -> Bool {
        (memberCodes[c.id] ?? "").trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("PZ")
    }
}
