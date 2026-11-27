import SwiftUI

/// Resultaat van een scan: kaart, stand in vakjes, aantal stempels kiezen, beloning inwisselen, ongedaan maken.
struct ScanResultSheet: View {
    let business: Business
    @State private var result: ScanResult
    @Environment(\.dismiss) private var dismiss
    @State private var amount = 1
    @State private var busy = false
    @State private var error: String?
    @State private var done: String?
    /// Tot wanneer "Ongedaan maken" zichtbaar is (2 minuten na de actie).
    @State private var undoUntil: Date?
    @State private var confirmRedeem = false
    @State private var successTick = 0
    @State private var errorTick = 0
    @State private var locations: [LocationOption] = []
    @State private var locationID = ""
    @State private var milestones: [Milestone] = []
    @State private var community: [CommunityReward] = []
    @State private var confirmCommunity: CommunityReward?

    init(business: Business, initial: ScanResult) {
        self.business = business
        _result = State(initialValue: initial)
        if initial.undoEventID != nil, let last = initial.lastStampAt, Date.now.timeIntervalSince(last) < 120 {
            _undoUntil = State(initialValue: last.addingTimeInterval(120))
        }
    }

    private var maxAmount: Int { max(1, min(30, result.maxPerScan ?? business.maxPerScan)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    StampCardView(name: result.cardName, business: result.business, color: result.color, logo: result.logo,
                                  total: result.stampsTotal, filled: result.stamps, reward: result.reward)
                    status
                    if !locations.isEmpty {
                        Picker("Vestiging", selection: $locationID) {
                            Text("Niet gekoppeld").tag("")
                            ForEach(locations) { loc in Text(loc.name).tag(loc.id) }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: locationID) { _, value in
                            UserDefaults.standard.set(value, forKey: "pasr.scan.location." + business.id)
                        }
                    }
                    if let cooldown = result.cooldownUntil, cooldown > .now {
                        cooldownNotice(until: cooldown)
                    }
                    if let error {
                        Label { Text(error) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.coral)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let done {
                        Label { Text(done) } icon: { Image(systemName: "checkmark.circle.fill") }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.mint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    stampControls
                    if result.isFull {
                        Button {
                            confirmRedeem = true
                        } label: {
                            Label("Beloning inwisselen", systemImage: "gift.fill")
                        }
                        .buttonStyle(BigButtonStyle(color: Theme.coral))
                        .disabled(busy)
                    }
                    if !milestones.isEmpty { milestoneControls }
                    if !community.isEmpty { communityControls }
                    undoButton
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(Text(verbatim: "…" + result.suffix))
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
                ToolbarItem(placement: .barLeading) {
                    Button {
                        Task { await reload() }
                    } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel(Text("Verversen"))
                    .disabled(busy)
                }
            }
            .task(id: result.stamps) { await loadMilestones(); await loadCommunity() }
            .task(id: business.id) { await loadLocations() }
            .sensoryFeedback(.success, trigger: successTick)
            .sensoryFeedback(.error, trigger: errorTick)
            .confirmationDialog("Beloning inwisselen?", isPresented: $confirmRedeem, titleVisibility: .visible) {
                Button("Inwisselen: \(result.reward)") { Task { await redeem() } }
                Button("Annuleer", role: .cancel) {}
            } message: {
                Text(String(format: String(localized: "Er gaan %lld stempels af."), result.stampsTotal))
            }
            .confirmationDialog("Gezamenlijke beloning uitgeven?",
                                isPresented: Binding(get: { confirmCommunity != nil }, set: { if !$0 { confirmCommunity = nil } }),
                                titleVisibility: .visible, presenting: confirmCommunity) { item in
                Button("Uitgeven: \(item.reward)") { Task { await claimCommunity(item) } }
                Button("Annuleer", role: .cancel) {}
            } message: { _ in
                Text("Een gezamenlijke beloning kan maar één keer per klant worden uitgegeven.")
            }
        }
    }

    private struct Milestone: Identifiable {
        let stamps: Int
        let title: String
        let available: Bool
        var id: Int { stamps }
        init?(_ data: [String: Any]) {
            guard let stamps = data["stamps"] as? Int,
                  let title = data["title"] as? String else { return nil }
            self.stamps = stamps
            self.title = title
            self.available = data["available"] as? Bool ?? false
        }
    }

    private var milestoneControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tussentijdse beloningen", systemImage: "gift.fill").font(.headline)
            ForEach(milestones) { milestone in
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(milestone.stamps) stempels").font(.subheadline.bold())
                        Text(milestone.title).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(milestone.available ? "Uitgeven" : "Niet beschikbaar") {
                        Task { await redeemMilestone(milestone) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || !milestone.available)
                }
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    @MainActor private func loadMilestones() async {
        do {
            let result = try await Account.shared.rpc("pasr_business_reward_progress",
                ["p_code": self.result.code])
            milestones = (result as? [[String: Any]] ?? []).compactMap(Milestone.init)
        } catch { milestones = [] }
    }

    @MainActor private func redeemMilestone(_ milestone: Milestone) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_reward_claim",
                ["p_code": result.code, "p_stamps": milestone.stamps])
            done = milestone.title + " uitgegeven"
            successTick += 1
            await loadMilestones()
        } catch { self.error = error.localizedDescription; errorTick += 1 }
    }

    /// Gezamenlijke winkelstraatactie waaraan deze zaak meedoet, met de voortgang van de gescande klant.
    private struct CommunityReward: Identifiable {
        let id: String
        let name: String
        let reward: String
        let visited: Int
        let required: Int
        let claimed: Bool
        var available: Bool { !claimed && visited >= required }
        init?(_ data: [String: Any]) {
            guard let j = JSONObject(data), let id = j.string("id"), let name = j.string("name") else { return nil }
            self.id = id
            self.name = name
            reward = j.string("reward") ?? ""
            visited = j.int("visited") ?? 0
            required = j.int("required") ?? 0
            claimed = j.bool("claimed") ?? false
        }
    }

    private var communityControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Gezamenlijke acties", systemImage: "person.3.fill").font(.headline)
            ForEach(community) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name).font(.subheadline.bold())
                        Text(item.reward).font(.footnote)
                        Text(item.claimed ? "Al uitgegeven" : "\(min(item.visited, item.required)) van \(item.required) winkels bezocht")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(item.claimed ? "Uitgegeven" : (item.available ? "Uitgeven" : "Nog niet")) {
                        confirmCommunity = item
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || !item.available)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    @MainActor private func loadCommunity() async {
        do {
            let list = try await Account.shared.rpc("pasr_business_community_member",
                ["p_business": business.id, "p_member_code": result.code])
            community = (list as? [[String: Any]] ?? []).compactMap(CommunityReward.init)
        } catch { community = [] }
    }

    @MainActor private func claimCommunity(_ item: CommunityReward) async {
        busy = true
        error = nil
        done = nil
        defer { busy = false }
        do {
            _ = try await Account.shared.rpc("pasr_business_community_claim",
                ["p_campaign": item.id, "p_business": business.id, "p_member_code": result.code])
            done = "Gezamenlijke beloning uitgegeven: " + item.reward
            successTick += 1
            await loadCommunity()
        } catch { self.error = error.localizedDescription; errorTick += 1 }
    }

    private struct LocationOption: Identifiable {
        let id: String
        let name: String
    }

    @MainActor private func loadLocations() async {
        guard let result = try? await Account.shared.rpc("pasr_business_locations_list", ["p_business": business.id]),
              let list = result as? [[String: Any]] else { return }
        locations = list.compactMap { x in
            guard x["active"] as? Bool == true,
                  let id = x["id"] as? String, let name = x["name"] as? String else { return nil }
            return LocationOption(id: id, name: name)
        }
        let stored = UserDefaults.standard.string(forKey: "pasr.scan.location." + business.id) ?? ""
        locationID = locations.contains(where: { $0.id == stored }) ? stored : ""
    }

    private var status: some View {
        VStack(spacing: 4) {
            Text(statusLine)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                if let last = result.lastStampAt {
                    Text("Laatste stempel \(last, style: .relative) geleden")
                } else {
                    Text("Nog geen stempels")
                }
                if result.rewardsRedeemed > 0 {
                    Text(verbatim: "·")
                    Text(String(format: String(localized: "%lldx beloning gehad"), result.rewardsRedeemed))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusLine: String {
        if result.stamps >= result.stampsTotal {
            return String(format: String(localized: "%lld van %lld, beloning klaar"), result.stamps, result.stampsTotal)
        }
        return String(format: String(localized: "%lld van %lld stempels"), result.stamps, result.stampsTotal)
    }

    private func cooldownNotice(until: Date) -> some View {
        Label {
            Text("Net al gestempeld. Weer mogelijk \(until, style: .relative).")
        } icon: {
            Image(systemName: "timer")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.amber)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var stampControls: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Aantal stempels").font(.headline)
                Spacer()
                Button {
                    amount = max(1, amount - 1)
                } label: {
                    Image(systemName: "minus").frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(amount <= 1)
                .accessibilityLabel(Text("Minder"))
                Text(verbatim: "\(amount)")
                    .font(.title.weight(.heavy).monospacedDigit())
                    .frame(minWidth: 44)
                    .contentTransition(.numericText())
                Button {
                    amount = min(maxAmount, amount + 1)
                } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(amount >= maxAmount)
                .accessibilityLabel(Text("Meer"))
            }
            .sensoryFeedback(.selection, trigger: amount)
            .accessibilityElement(children: .contain)
            .accessibilityValue(Text(verbatim: "\(amount)"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: amount = min(maxAmount, amount + 1)
                case .decrement: amount = max(1, amount - 1)
                @unknown default: break
                }
            }
            Button {
                Task { await stamp() }
            } label: {
                if busy {
                    ProgressView().tint(.black)
                } else {
                    Label(amount == 1 ? String(localized: "Stempel toevoegen") : String(format: String(localized: "%lld stempels toevoegen"), amount),
                          systemImage: "plus.circle.fill")
                }
            }
            .buttonStyle(BigButtonStyle(color: Theme.mint, foreground: .black))
            .disabled(busy)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
    }

    @ViewBuilder private var undoButton: some View {
        if result.undoEventID != nil, let until = undoUntil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if until > context.date {
                    Button {
                        Task { await undo() }
                    } label: {
                        Label {
                            Text(String(format: String(localized: "Ongedaan maken (%@)"), Self.clock(until.timeIntervalSince(context.date))))
                        } icon: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                }
            }
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Acties

    private func run(_ message: String, _ action: () async throws -> ScanResult?, undoable: Bool) async {
        busy = true
        error = nil
        done = nil
        defer { busy = false }
        do {
            let new = try await action()
            withAnimation(.spring(duration: 0.35)) {
                if let new { result = new }
                done = message
                undoUntil = undoable ? Date.now.addingTimeInterval(120) : nil
            }
            if new == nil { await reload(quiet: true) }
            successTick += 1
        } catch {
            withAnimation { self.error = error.localizedDescription }
            errorTick += 1
        }
    }

    private func stamp() async {
        let n = amount
        let message = n == 1 ? String(localized: "Stempel gezet") : String(format: String(localized: "%lld stempels gezet"), n)
        await run(message, { try await BusinessAPI.stamp(result.code, amount: n, location: locationID.isEmpty ? nil : locationID) }, undoable: true)
        if error == nil { amount = 1 }
    }

    private func redeem() async {
        await run(String(localized: "Beloning ingewisseld"), { try await BusinessAPI.redeem(result.code) }, undoable: true)
    }

    private func undo() async {
        guard let event = result.undoEventID else { return }
        await run(String(localized: "Ongedaan gemaakt"), { try await BusinessAPI.undo(event: event, code: result.code) }, undoable: false)
    }

    private func reload(quiet: Bool = false) async {
        do {
            let fresh = try await BusinessAPI.scan(result.code)
            withAnimation { result = fresh }
        } catch {
            if !quiet { self.error = error.localizedDescription }
        }
    }
}
