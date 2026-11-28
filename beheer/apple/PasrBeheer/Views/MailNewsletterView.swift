import SwiftUI

/// Nieuwsbrief: doelgroep Gebruikers of Ondernemers (aantal), merk, onderwerp, Markdown, voorbeeld, testmail,
/// versturen met bevestiging en het overzicht van eerdere nieuwsbrieven (`mail_campaign_*`).
struct MailNewsletterView: View {
    let status: MailStatus?
    @ObservedObject var draft: NewsletterDraft

    @EnvironmentObject private var session: Session
    @State private var count: Int?
    @State private var countError: String?
    @State private var campaigns: [MailCampaign] = []
    @State private var sending = false
    @State private var confirming = false
    @State private var result: String?
    @State private var error: String?
    @State private var showPreview = true
    @State private var cancelling: MailCampaign?

    private var subjectText: String { draft.subject.trimmingCharacters(in: .whitespaces) }
    private var bodyText: String { draft.body.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasSending: Bool { campaigns.contains { $0.status == "sending" } }
    private var canSend: Bool {
        !sending && (count ?? 0) > 0 && !subjectText.isEmpty && !bodyText.isEmpty && status?.smtp != false
    }

    var body: some View {
        Form {
            Section {
                Picker("Doelgroep", selection: $draft.audience) {
                    Text("Gebruikers").tag("users")
                    Text("Ondernemers").tag("owners")
                }
                .pickerStyle(.segmented)
                LabeledContent("Ontvangers", value: count.map(Fmt.n) ?? "–")
                if let countError { Text(countError).font(.caption).foregroundStyle(Theme.coral) }
                Picker("Merk", selection: $draft.brand) {
                    ForEach(MailBrand.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Doelgroep")
            } footer: {
                Text("Gebruikers: bevestigde Pasr-accounts. Ondernemers: eigenaren en medewerkers van een zaak. Wie zich heeft afgemeld, krijgt niets. Je ziet alleen aantallen, nooit adressen. Elke mail krijgt zelf een afmeldlink.")
            }

            Section {
                TextField("Onderwerp", text: $draft.subject)
            } header: {
                Text("Onderwerp")
            } footer: {
                if let from = status?.from(draft.brand) { Text(verbatim: String(localized: "Afzender: ") + from) }
            }

            Section("Bericht") {
                MailBodyEditor(text: $draft.body)
                MailSignatureToggle(isOn: $draft.signature, brand: draft.brand)
            }

            Section("Voorbeeld") {
                Toggle("Voorbeeld tonen", isOn: $showPreview)
                if showPreview { MailPreviewSection(markdown: draft.body, brand: draft.brand, subject: draft.subject, signature: draft.signature) }
            }

            Section("Testmail") {
                MailTestRow(address: $draft.testAddress, markdown: draft.body, brand: draft.brand, subject: draft.subject, signature: draft.signature)
            }

            Section {
                Button { confirming = true } label: {
                    HStack { Spacer(); if sending { ProgressView() } else { Label("Nieuwsbrief versturen", systemImage: "paperplane.fill").bold() }; Spacer() }
                }
                .disabled(!canSend)
                if status?.smtp == false {
                    Text("E-mail versturen is op de server nog niet ingesteld.").font(.caption).foregroundStyle(Theme.amber)
                }
                if let error { Text(error).foregroundStyle(Theme.coral).font(.subheadline) }
                if let result { Text(result).foregroundStyle(Theme.mint).font(.subheadline) }
            }

            if !campaigns.isEmpty {
                Section("Eerdere nieuwsbrieven") {
                    ForEach(campaigns) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(verbatim: c.subject ?? "").bold().lineLimit(2)
                                Spacer()
                                MailBrandBadge(brand: c.brand)
                            }
                            Text(verbatim: progress(c))
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                            Text(verbatim: [MailLabels.audience(c.audience), MailLabels.campaignStatus(c.status), Fmt.ago(c.created_at)].joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.muted)
                            if c.status == "sending" {
                                Button("Annuleren", role: .destructive) { cancelling = c }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .refreshable { await loadCampaigns(); await loadCount() }
        .task(id: session.refreshTick) { await loadCampaigns() }
        .task(id: draft.audience) { await loadCount() }
        .task(id: hasSending) {
            while hasSending && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await loadCampaigns()
            }
        }
        .onChange(of: draft.audience) { _, a in draft.brand = a == "owners" ? .zakelijk : .pasr }
        .confirmationDialog("Nieuwsbrief versturen?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Versturen naar \(Fmt.n(count ?? 0)) ontvangers") { Task { await send() } }
        } message: {
            Text(String(localized: "\(MailLabels.audience(draft.audience)), als \(draft.brand.title). Dit kan niet worden teruggedraaid.") + signatureNote(draft.signature, draft.brand))
        }
        .confirmationDialog("Verzenden annuleren?", isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }), titleVisibility: .visible) {
            Button("Annuleren", role: .destructive) { if let c = cancelling { Task { await cancel(c) } } }
        } message: {
            Text("Mails die al zijn verstuurd, blijven verstuurd.")
        }
    }

    private func progress(_ c: MailCampaign) -> String {
        var s = String(localized: "\(Fmt.n(c.sent ?? 0)) van \(Fmt.n(c.recipients ?? 0)) verstuurd")
        if let f = c.failed, f > 0 { s += " · " + String(localized: "\(f) mislukt") }
        return s
    }

    private func loadCount() async {
        count = nil
        do {
            count = try await session.call("mail_campaign_audience", ["audience": draft.audience], as: MailAudienceCount.self).count
            countError = nil
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch { countError = error.mailText }
    }

    private func loadCampaigns() async {
        do {
            campaigns = try await session.call("mail_campaign_list", as: MailCampaignList.self).items
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch { self.error = error.mailText }
    }

    private func send() async {
        guard canSend else { return }
        sending = true; result = nil; error = nil
        defer { sending = false }
        let p: [String: Any] = ["audience": draft.audience, "brand": draft.brand.rawValue, "subject": subjectText,
                                "body_md": bodyText, "request_id": draft.requestID, "signature": draft.signature]
        do {
            let r = try await session.call("mail_campaign_send", p, as: MailCampaignSendResponse.self, timeout: 90)
            result = String(localized: "De nieuwsbrief wordt verstuurd naar \(Fmt.n(r.recipients ?? 0)) ontvangers.")
            draft.clear()
            await loadCampaigns()
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch { self.error = error.mailText }
    }

    private func cancel(_ c: MailCampaign) async {
        do {
            try await session.call("mail_campaign_cancel", ["id": c.id])
            await loadCampaigns()
        } catch is CancellationError {
        } catch { self.error = error.mailText }
    }
}
