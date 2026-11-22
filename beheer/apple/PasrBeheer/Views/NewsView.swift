import SwiftUI

/// Bericht sturen: een pushmelding aan gebruikers van Pasr met de opt-in "Nieuws over mijn kaarten".
/// Doelgroep, voorbeeld, aantal ontvangers, versturen en geschiedenis (zelfde als beheer.pasr.nl › Berichten).
struct NewsView: View {
    @EnvironmentObject private var session: Session
    @State private var overview: NewsOverview?
    @State private var title = ""
    @State private var message = ""
    @State private var audience: NewsAudience = .all
    @State private var store = ""
    @State private var count: Int?
    @State private var split: NewsCount?
    @State private var error: String?
    @State private var result: String?
    @State private var confirming = false
    @State private var sending = false

    private var storeID: String { store.trimmingCharacters(in: .whitespaces).lowercased() }
    private var params: [String: Any] {
        var p: [String: Any] = ["audience": audience.rawValue]
        if audience == .store { p["store"] = storeID }
        return p
    }

    var body: some View {
        Form {
            if let overview {
                Section {
                    LabeledContent("Met opt-in", value: Fmt.n(overview.all))
                    LabeledContent("Nieuw deze week", value: Fmt.n(overview.new))
                    LabeledContent("Inactief (30 dagen)", value: Fmt.n(overview.inactive))
                } footer: {
                    Text(overview.push_ready == false ? "Pushmeldingen zijn op de server nog niet ingericht." : "Alleen apparaten met \u{201C}Nieuws over mijn kaarten\u{201D} aan. Er gaan geen kaartnummers of namen mee.")
                }
            }
            Section("Bericht") {
                TextField("Titel (optioneel)", text: $title)
                TextField("Bericht", text: $message, axis: .vertical)
                    .lineLimit(3...8)
                    .onChange(of: message) { _, v in if v.count > 240 { message = String(v.prefix(240)) } }
                Text("\(240 - message.count) tekens over").font(.caption).foregroundStyle(Theme.muted)
            }
            Section("Doelgroep") {
                Picker("Doelgroep", selection: $audience) {
                    ForEach(NewsAudience.allCases) { Text($0.title).tag($0) }
                }
                if audience == .store {
                    TextField("Winkel-id, bijv. ah", text: $store)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    if let stores = overview?.stores, !stores.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(stores.prefix(30), id: \.self) { s in
                                    Button("\(s.id) (\(Fmt.n(s.count)))") { store = s.id }
                                        .buttonStyle(.bordered).controlSize(.small)
                                }
                            }
                        }
                    }
                }
                LabeledContent("Ontvangers", value: count.map(Fmt.n) ?? "–")
                if let split, let ios = split.ios {
                    LabeledContent("Per platform", value: "iOS \(Fmt.n(ios)) · Android \(Fmt.n(split.android ?? 0))")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            Section("Voorbeeld") {
                HStack(alignment: .top, spacing: 10) {
                    Image("Logo").resizable().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text(title.isEmpty ? "Pasr" : title).bold(); Spacer(); Text("nu").font(.caption).foregroundStyle(Theme.muted) }
                        Text(message.isEmpty ? "Je bericht verschijnt hier." : message).font(.subheadline)
                    }
                }
                .padding(10)
                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Section {
                Button {
                    confirming = true
                } label: {
                    HStack { Spacer(); if sending { ProgressView() } else { Label("Versturen", systemImage: "paperplane.fill").bold() }; Spacer() }
                }
                .disabled(sending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (count ?? 0) == 0)
                if let error { Text(error).foregroundStyle(Theme.coral).font(.subheadline) }
                if let result { Text(result).foregroundStyle(Theme.mint).font(.subheadline) }
            }
            if let history = overview?.history, !history.isEmpty {
                Section("Geschiedenis") {
                    ForEach(history) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(c.title ?? "Pasr").bold()
                                Spacer()
                                Text("\(Fmt.n(c.sent)) van \(Fmt.n(c.recipients))").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                            }
                            Text(c.body).font(.subheadline)
                            Text("\((NewsAudience(rawValue: c.audience)?.title ?? c.audience))\(c.store_id.map { " " + $0 } ?? "") · \(Fmt.ago(c.created_at))\(c.failed > 0 ? " · \(c.failed) mislukt" : "")")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Bericht sturen")
        .refreshable { await load() }
        .task(id: session.refreshTick) { await load() }
        .task(id: "\(audience.rawValue)|\(storeID)|\(overview?.all ?? -1)") { await updateCount() }
        .confirmationDialog("Bericht versturen?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Versturen naar \(Fmt.plural(count ?? 0, "apparaat", "apparaten"))") { Task { await send() } }
        } message: {
            Text("Dit kan niet worden teruggedraaid.")
        }
    }

    private func load() async {
        do {
            overview = try await session.call("news_overview", as: NewsOverview.self)
            error = nil
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch { self.error = error.localizedDescription }
    }

    private func updateCount() async {
        // altijd via news_count: telt iOS (APNs) en Android (FCM) apart
        if audience != .store, let overview, split == nil {
            count = audience == .all ? overview.all : audience == .new ? overview.new : overview.inactive
        }
        guard audience != .store || storeID.range(of: "^[a-z0-9-]{2,40}$", options: .regularExpression) != nil else { count = nil; split = nil; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        if let c = try? await session.call("news_count", params, as: NewsCount.self) { count = c.count; split = c }
    }

    private func send() async {
        sending = true; result = nil; error = nil
        defer { sending = false }
        var p = params
        p["body"] = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { p["title"] = t }
        do {
            let r = try await session.call("news_send", p, as: NewsSendResponse.self)
            result = "Verstuurd naar \(Fmt.n(r.sent)) van \(Fmt.n(r.recipients)) apparaten" + (r.failed > 0 ? " (\(r.failed) mislukt)." : ".")
                + (r.android.map { a in " iOS \(Fmt.n(r.ios?.sent ?? 0)) van \(Fmt.n(r.ios?.recipients ?? 0)), Android \(Fmt.n(a.sent)) van \(Fmt.n(a.recipients))." } ?? "")
            message = ""; title = ""
            await load()
        } catch { self.error = error.localizedDescription }
    }
}
