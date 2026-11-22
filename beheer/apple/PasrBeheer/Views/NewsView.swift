import SwiftUI

/// Bericht sturen: een pushmelding aan gebruikers van Pasr met de opt-in "Nieuws over mijn kaarten", of aan iedereen
/// met meldingen aan (Pasr, Pasr Zakelijk of beide). Platform Alles/Apple/Android, optioneel een https-link die een tik
/// op de melding opent. Doelgroep, voorbeeld, aantal ontvangers per platform, versturen en geschiedenis (zelfde als
/// beheer.pasr.nl › Berichten).
struct NewsView: View {
    @EnvironmentObject private var session: Session
    @State private var overview: NewsOverview?
    @State private var title = ""
    @State private var message = ""
    @State private var audience: NewsAudience = .all
    @State private var platform: NewsPlatform = .all
    @State private var app: NewsApp = .pasr
    @State private var link = ""
    @State private var store = ""
    @State private var count: Int?
    @State private var split: NewsCount?
    @State private var error: String?
    @State private var result: String?
    @State private var confirming = false
    @State private var sending = false

    private var storeID: String { store.trimmingCharacters(in: .whitespaces).lowercased() }
    private var params: [String: Any] {
        var p: [String: Any] = ["audience": audience.rawValue, "platform": platform.rawValue]
        if audience == .store { p["store"] = storeID }
        if audience == .everyone { p["app"] = app.rawValue }
        return p
    }
    private var linkText: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Alleen https, hoogstens 500 tekens, met een echte hostnaam (de server controleert het ook).
    private var linkURL: URL? { Self.validLink(linkText) }
    private var linkOK: Bool { linkText.isEmpty || linkURL != nil }
    private var previewTitle: String {
        let t = title.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { return t }
        return audience == .everyone && app == .zakelijk ? "Pasr Zakelijk" : "Pasr"
    }

    static func validLink(_ s: String) -> URL? {
        guard !s.isEmpty, s.count <= 500, s.lowercased().hasPrefix("https://"),
              s.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let u = URL(string: s), u.scheme?.lowercased() == "https", u.user == nil, u.password == nil,
              let host = u.host, host.contains("."), u.port == nil || u.port == 443 else { return nil }
        return u
    }

    var body: some View {
        Form {
            if let overview {
                Section {
                    LabeledContent("Met opt-in", value: Fmt.n(overview.all))
                    LabeledContent("Nieuw deze week", value: Fmt.n(overview.new))
                    LabeledContent("Inactief (30 dagen)", value: Fmt.n(overview.inactive))
                    if let e = overview.everyone {
                        LabeledContent("Meldingen aan in Pasr", value: "Apple \(Fmt.n(e.pasr?.ios ?? 0)) · Android \(Fmt.n(e.pasr?.android ?? 0))")
                        LabeledContent("Meldingen aan in Pasr Zakelijk", value: "Apple \(Fmt.n(e.zakelijk?.ios ?? 0)) · Android \(Fmt.n(e.zakelijk?.android ?? 0))")
                    }
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
                TextField("Link (optioneel)", text: $link, prompt: Text(verbatim: "https://pasr.nl/…"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onChange(of: link) { _, v in if v.count > 500 { link = String(v.prefix(500)) } }
                Text(linkOK ? "Alleen https. Een tik op de melding opent deze link." : "Geen geldige https-link.")
                    .font(.caption).foregroundStyle(linkOK ? Theme.muted : Theme.coral)
            }
            Section("Doelgroep") {
                Picker("Doelgroep", selection: $audience) {
                    ForEach(NewsAudience.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                if audience == .everyone {
                    Picker("App", selection: $app) {
                        ForEach(NewsApp.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                    }
                }
                Picker("Platform", selection: $platform) {
                    ForEach(NewsPlatform.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                if audience == .everyone {
                    Label("Alleen voor belangrijke berichten, geen reclame. Deze melding gaat ook naar mensen zonder opt-in voor nieuws (Apple-richtlijn 4.5.4).",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.amber)
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
                    LabeledContent("Per platform", value: "Apple \(Fmt.n(ios)) · Android \(Fmt.n(split.android ?? 0))")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            Section("Voorbeeld") {
                HStack(alignment: .top, spacing: 10) {
                    Image("Logo").resizable().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text(verbatim: previewTitle).bold(); Spacer(); Text("nu").font(.caption).foregroundStyle(Theme.muted) }
                        if message.isEmpty { Text("Je bericht verschijnt hier.").font(.subheadline) } else { Text(verbatim: message).font(.subheadline) }
                        if let linkURL {
                            Text(verbatim: linkURL.absoluteString).font(.caption).foregroundStyle(Theme.mint).lineLimit(2)
                        }
                    }
                }
                .padding(10)
                .background(Theme.card2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(linkURL != nil ? "Een tik op de melding opent deze link (in de app; links van pasr.nl openen de juiste plek in Pasr)."
                     : "Een tik opent de app; bij de doelgroep \u{201C}heeft een kaart van\u{201D} opent de kaart van die winkel.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Section {
                Button {
                    confirming = true
                } label: {
                    HStack { Spacer(); if sending { ProgressView() } else { Label("Versturen", systemImage: "paperplane.fill").bold() }; Spacer() }
                }
                .disabled(sending || !linkOK || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (count ?? 0) == 0)
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
                            if let u = c.url, let url = URL(string: u) {
                                Link(destination: url) { Text(verbatim: u).font(.caption).lineLimit(2) }
                            }
                            Text(verbatim: historyLine(c))
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
        .task(id: "\(audience.rawValue)|\(storeID)|\(platform.rawValue)|\(app.rawValue)|\(overview?.all ?? -1)") { await updateCount() }
        .confirmationDialog("Bericht versturen?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Versturen naar \(Fmt.plural(count ?? 0, "apparaat", "apparaten"))") { Task { await send() } }
        } message: {
            if audience == .everyone {
                Text("Alleen voor belangrijke berichten, geen reclame. Dit kan niet worden teruggedraaid.")
            } else {
                Text("Dit kan niet worden teruggedraaid.")
            }
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

    private func historyLine(_ c: NewsCampaign) -> String {
        var s = NewsAudience(rawValue: c.audience).map { String(localized: String.LocalizationValue($0.title)) } ?? c.audience
        if let id = c.store_id { s += " " + id }
        if c.audience == NewsAudience.everyone.rawValue, let a = c.app.flatMap(NewsApp.init(rawValue:)) {
            s += " · " + (a == .both ? "Pasr + Pasr Zakelijk" : a.title)
        }
        if let p = c.platform.flatMap(NewsPlatform.init(rawValue:)), p != .all { s += " · " + p.title }
        s += " · " + Fmt.ago(c.created_at)
        if c.failed > 0 { s += " · " + String(localized: "\(c.failed) mislukt") }
        return s
    }

    private func updateCount() async {
        // altijd via news_count: telt Apple (APNs) en Android (FCM) apart
        if audience != .store, audience != .everyone, platform == .all, let overview, split == nil {
            count = audience == .all ? overview.all : audience == .new ? overview.new : overview.inactive
        }
        guard audience != .store || storeID.range(of: "^[a-z0-9-]{2,40}$", options: .regularExpression) != nil else { count = nil; split = nil; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        if let c = try? await session.call("news_count", params, as: NewsCount.self) { count = c.count; split = c }
    }

    private func send() async {
        guard !sending else { return }   // dubbel versturen voorkomen (de server weigert het ook: duplicate)
        sending = true; result = nil; error = nil
        defer { sending = false }
        var p = params
        p["body"] = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if let linkURL { p["url"] = linkURL.absoluteString }
        let t = title.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { p["title"] = t }
        do {
            let r = try await session.call("news_send", p, as: NewsSendResponse.self)
            result = "Verstuurd naar \(Fmt.n(r.sent)) van \(Fmt.n(r.recipients)) apparaten" + (r.failed > 0 ? " (\(r.failed) mislukt)." : ".")
                + (r.android.map { a in " Apple \(Fmt.n(r.ios?.sent ?? 0)) van \(Fmt.n(r.ios?.recipients ?? 0)), Android \(Fmt.n(a.sent)) van \(Fmt.n(a.recipients))." } ?? "")
            message = ""; title = ""; link = ""
            await load()
        } catch { self.error = error.localizedDescription }
    }
}
