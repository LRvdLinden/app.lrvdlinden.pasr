import SwiftUI

/// De kaartgebonden instellingen zijn echt en worden via de bestaande Supabase-accountsession opgeslagen.
/// Alleen de eigenaar mag instellingen wijzigen. Campagnes vereisen server-side verwerking voor automatische uitvoering.
struct LoyaltyProgramView: View {
    let card: BusinessCard
    @Environment(\.dismiss) private var dismiss
    @State private var rewardsOn = false
    @State private var rewardsText = ""
    @State private var retentionOn = false
    @State private var retentionDays = 30
    @State private var referralOn = false
    @State private var referralBonus = 1
    @State private var campaignOn = false
    @State private var campaignMultiplier = 2
    @State private var campaignWeekday = 2
    @State private var campaignStart = Date()
    @State private var campaignEnd = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var vipOn = false
    @State private var silver = 10
    @State private var gold = 25
    @State private var locationsOn = false
    @State private var locationNames = ""
    @State private var marketingOn = false
    @State private var marketingName = ""
    @State private var communityOn = false
    @State private var communityName = ""
    @State private var info = false
    @State private var loading = true
    @State private var saving = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Stempelkaart", value: card.name)
                }
                Section {
                    Toggle("Meerdere beloningen", isOn: $rewardsOn)
                    if rewardsOn {
                        Text("Eén mijlpaal per regel. Bijvoorbeeld: 3: Gratis koekje")
                            .font(.footnote).foregroundStyle(.secondary)
                        TextEditor(text: $rewardsText).frame(minHeight: 100)
                    }
                } header: { Label("Beloningen", systemImage: "gift") } footer: {
                    Text("Beloningen worden alleen door de ondernemer vrijgegeven; de klant kan nooit zelf stempels zetten.")
                }
                Section {
                    Toggle("Terugkomactie", isOn: $retentionOn)
                    if retentionOn { Stepper("Na \(retentionDays) dagen", value: $retentionDays, in: 7...365) }
                } header: { Label("Terugkomacties", systemImage: "bell") }
                Section {
                    HStack {
                        Toggle("Vrienden uitnodigen", isOn: $referralOn)
                        Button { info = true } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Uitleg vrienden uitnodigen")
                    }
                    if referralOn { Stepper("\(referralBonus) extra stempel(s)", value: $referralBonus, in: 1...3) }
                } header: { Label("Vrienden uitnodigen", systemImage: "person.2") }
                Section {
                    Toggle("Tijdelijke stempelactie", isOn: $campaignOn)
                    if campaignOn {
                        Stepper("\(campaignMultiplier) keer stempels", value: $campaignMultiplier, in: 1...3)
                        DatePicker("Start actie", selection: $campaignStart, displayedComponents: .date)
                        DatePicker("Einde actie", selection: $campaignEnd, in: campaignStart..., displayedComponents: .date)
                        Picker("Actiedag", selection: $campaignWeekday) {
                            Text("Elke dag").tag(-1)
                            ForEach(0..<7, id: \.self) { day in
                                Text(["Zondag", "Maandag", "Dinsdag", "Woensdag", "Donderdag", "Vrijdag", "Zaterdag"][day]).tag(day)
                            }
                        }
                    }
                } header: { Label("Acties", systemImage: "bolt") }
                Section {
                    Toggle("VIP-niveaus", isOn: $vipOn)
                    if vipOn {
                        Stepper("Zilver vanaf \(silver) bezoeken", value: $silver, in: 1...1000)
                        Stepper("Goud vanaf \(gold) bezoeken", value: $gold, in: (silver+1)...2000)
                    }
                } header: { Label("VIP", systemImage: "crown") }
                Section {
                    Toggle("Meerdere vestigingen", isOn: $locationsOn)
                    if locationsOn {
                        Text("Voer één vestiging per regel in.")
                            .font(.footnote).foregroundStyle(.secondary)
                        TextEditor(text: $locationNames).frame(minHeight: 80)
                    }
                } header: { Label("Vestigingen", systemImage: "mappin.and.ellipse") }
                Section {
                    Toggle("Marketingkalender", isOn: $marketingOn)
                    if marketingOn { TextField("Campagnenaam", text: $marketingName) }
                    Toggle("Gezamenlijke winkelstraatactie", isOn: $communityOn)
                    if communityOn { TextField("Naam gezamenlijke actie", text: $communityName) }
                } header: { Label("Marketing en samenwerking", systemImage: "calendar") }
                if let message {
                    Section { Text(message).font(.subheadline) }
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if saving { ProgressView() }
                            Text("Instellingen opslaan")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(loading || saving)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Acties en beloningen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Klaar") { dismiss() }
            } }
            .alert("Vrienden uitnodigen", isPresented: $info) {
                Button("Begrepen", role: .cancel) {}
            } message: {
                Text("De ondernemer activeert de actie per kaart. De klant deelt een uitnodigingslink. Bonusstempels mogen pas worden toegekend na een geverifieerde eerste aankoop, nooit alleen na de aanmelding. Zelfuitnodigingen tellen niet mee.")
            }
            .task { await load() }
        }
    }

    @MainActor private func load() async {
        defer { loading = false }
        do {
            let json = try await Account.shared.rpc("pasr_business_program", ["p_card": card.id])
            let settings = JSONObject(json)?.object("settings")
            let rewards = settings?.array("rewards") ?? []
            rewardsOn = !rewards.isEmpty
            rewardsText = rewards.map { "\($0.int("stamps") ?? 0): \($0.string("title") ?? "")" }.joined(separator: "\n")
            let retention = settings?.object("retention")
            retentionOn = retention?.bool("enabled") ?? false
            retentionDays = retention?.int("days") ?? 30
            let referral = settings?.object("referral")
            referralOn = referral?.bool("enabled") ?? false
            referralBonus = referral?.int("bonus") ?? 1
            let campaign = settings?.object("campaign")
            campaignOn = campaign?.bool("enabled") ?? false
            campaignMultiplier = campaign?.int("multiplier") ?? 2
            campaignWeekday = campaign?.int("weekday") ?? 2
            let dateFormat = DateFormatter()
            dateFormat.locale = Locale(identifier: "en_US_POSIX")
            dateFormat.dateFormat = "yyyy-MM-dd"
            if let raw = campaign?.string("start"), let date = dateFormat.date(from: raw) { campaignStart = date }
            if let raw = campaign?.string("end"), let date = dateFormat.date(from: raw) { campaignEnd = date }
            let vip = settings?.object("vip")
            vipOn = vip?.bool("enabled") ?? false
            silver = vip?.int("silver") ?? 10
            gold = vip?.int("gold") ?? 25
            let locations = settings?.object("locations")
            locationsOn = locations?.bool("enabled") ?? false
            locationNames = (locations?.raw["names"] as? [String] ?? []).joined(separator: "\n")
            let marketing = settings?.object("marketing")
            marketingOn = marketing?.bool("enabled") ?? false
            marketingName = marketing?.string("name") ?? ""
            let community = settings?.object("community")
            communityOn = community?.bool("enabled") ?? false
            communityName = community?.string("name") ?? ""
        } catch { message = error.localizedDescription }
    }

    @MainActor private func save() async {
        saving = true
        defer { saving = false }
        var rewards: [[String: Any]] = []
        if rewardsOn {
            for line in rewardsText.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, let n = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                      n >= 2, n <= card.stampsTotal, parts[1].trimmingCharacters(in: .whitespaces).count >= 3 else {
                    message = "Gebruik per regel: 3: Gratis koekje (binnen het aantal stempels)."
                    return
                }
                rewards.append(["stamps": n, "title": parts[1].trimmingCharacters(in: .whitespaces)])
            }
            rewards.sort { ($0["stamps"] as? Int ?? 0) < ($1["stamps"] as? Int ?? 0) }
        }
        guard rewards.count <= 8, Set(rewards.compactMap { $0["stamps"] as? Int }).count == rewards.count else {
            message = "Maximaal acht verschillende mijlpalen per kaart."; return
        }
        guard gold > silver else { message = "Goud moet boven Zilver liggen."; return }
        guard campaignEnd >= campaignStart else { message = "Actie eindigt vóór de startdatum."; return }
        let dateFormat = DateFormatter()
        dateFormat.locale = Locale(identifier: "en_US_POSIX")
        dateFormat.dateFormat = "yyyy-MM-dd"
        let settings: [String: Any] = [
            "rewards": rewards,
            "retention": ["enabled": retentionOn, "days": retentionDays],
            "referral": ["enabled": referralOn, "bonus": referralBonus],
            "campaign": ["enabled": campaignOn, "multiplier": campaignMultiplier, "weekday": campaignWeekday,
                         "start": dateFormat.string(from: campaignStart),
                         "end": dateFormat.string(from: campaignEnd)],
            "vip": ["enabled": vipOn, "silver": silver, "gold": gold],
            "locations": ["enabled": locationsOn, "names": locationNames.split(whereSeparator: \.isNewline).map(String.init)],
            "marketing": ["enabled": marketingOn, "name": String(marketingName.prefix(80))],
            "community": ["enabled": communityOn, "name": String(communityName.prefix(80))]
        ]
        do {
            _ = try await Account.shared.rpc("pasr_business_program", ["p_card": card.id, "p_settings": settings])
            message = "Kaartinstellingen opgeslagen. Automatische terugkomberichten worden pas verstuurd wanneer klanten hiervoor toestemming hebben gegeven en de verzendservice actief is."
        } catch { message = error.localizedDescription }
    }
}
