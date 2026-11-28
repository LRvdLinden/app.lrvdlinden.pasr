import SwiftUI

/// Nieuwe mail: Aan, CC en BCC (alle drie altijd zichtbaar, meerdere adressen per veld), merk, onderwerp,
/// Markdown, bijlagen, voorbeeld, testmail en versturen met bevestiging (`mail_compose`).
struct MailComposeView: View {
    let status: MailStatus?
    @ObservedObject var draft: ComposeDraft

    @EnvironmentObject private var session: Session
    @State private var sending = false
    @State private var confirming = false
    @State private var result: String?
    @State private var error: String?
    @State private var showPreview = true

    private var total: Int { draft.toList.valid.count + draft.ccList.valid.count + draft.bccList.valid.count }
    private var anyInvalid: Bool { !draft.toList.invalid.isEmpty || !draft.ccList.invalid.isEmpty || !draft.bccList.invalid.isEmpty }
    private var subjectText: String { draft.subject.trimmingCharacters(in: .whitespaces) }
    private var bodyText: String { draft.body.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool {
        !sending && !anyInvalid && (draft.toList.valid.count + draft.bccList.valid.count) > 0 && total <= MailLimits.recipients
            && !subjectText.isEmpty && !bodyText.isEmpty && draft.attachmentBytes <= MailLimits.attachmentBytes
            && status?.smtp != false
    }

    var body: some View {
        Form {
            Section {
                MailAddressField(title: "Aan", prompt: "Adressen (komma, spatie of regel)", text: $draft.to)
                MailAddressField(title: "CC", prompt: "Adressen in kopie", text: $draft.cc)
                MailAddressField(title: "BCC", prompt: "Verborgen adressen: plak hier een hele lijst", text: $draft.bcc)
                HStack {
                    Text("Totaal").foregroundStyle(Theme.muted)
                    Spacer()
                    (total == 1 ? Text("1 adres") : Text("\(total) adressen"))
                        .monospacedDigit().foregroundStyle(total > MailLimits.recipients ? Theme.coral : Color.primary)
                }
                .font(.subheadline)
            } header: {
                Text("Ontvangers")
            } footer: {
                Text("Hoogstens 200 adressen per mail. Ontvangers in BCC zien elkaar niet. Zonder Aan gaat de mail naar de afzender zelf, met de BCC-adressen verborgen.")
            }

            Section {
                Picker("Merk", selection: $draft.brand) {
                    ForEach(MailBrand.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Onderwerp", text: $draft.subject)
            } header: {
                Text("Afzender en onderwerp")
            } footer: {
                if let from = status?.from(draft.brand) { Text(verbatim: String(localized: "Afzender: ") + from) }
            }

            Section("Bericht") { MailBodyEditor(text: $draft.body) }

            Section {
                MailAttachmentsRows(attachments: $draft.attachments)
            } header: { Text("Bijlagen") } footer: { Text("Samen hoogstens 10 MB.") }

            Section("Voorbeeld") {
                Toggle("Voorbeeld tonen", isOn: $showPreview)
                if showPreview { MailPreviewSection(markdown: draft.body, brand: draft.brand, subject: draft.subject) }
            }

            Section("Testmail") {
                MailTestRow(address: $draft.testAddress, markdown: draft.body, brand: draft.brand, subject: draft.subject)
            }

            Section {
                Button { confirming = true } label: {
                    HStack { Spacer(); if sending { ProgressView() } else { Label("Versturen", systemImage: "paperplane.fill").bold() }; Spacer() }
                }
                .disabled(!canSend)
                if status?.smtp == false {
                    Text("E-mail versturen is op de server nog niet ingesteld.").font(.caption).foregroundStyle(Theme.amber)
                }
                if let error { Text(error).foregroundStyle(Theme.coral).font(.subheadline) }
                if let result { Text(result).foregroundStyle(Theme.mint).font(.subheadline) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .confirmationDialog("Mail versturen?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Versturen") { Task { await send() } }
        } message: {
            Text(confirmMessage)
        }
    }

    private var confirmMessage: String {
        let t = draft.toList.valid.count, c = draft.ccList.valid.count, b = draft.bccList.valid.count
        return String(localized: "\(total) adressen (aan \(t), cc \(c), bcc \(b)), als \(draft.brand.title). Dit kan niet worden teruggedraaid.")
    }

    private func send() async {
        guard canSend else { return }
        sending = true; result = nil; error = nil
        defer { sending = false }
        var p: [String: Any] = ["subject": subjectText, "body_md": bodyText, "brand": draft.brand.rawValue, "thread": true,
                                "to": draft.toList.valid]
        if !draft.ccList.valid.isEmpty { p["cc"] = draft.ccList.valid }
        if !draft.bccList.valid.isEmpty { p["bcc"] = draft.bccList.valid }
        if !draft.attachments.isEmpty { p["attachments"] = draft.attachments.map { $0.json } }
        do {
            let r = try await session.call("mail_compose", p, as: MailComposeResponse.self, timeout: 120)
            let sent = r.sent ?? 0, failed = r.failed ?? 0
            var s = String(localized: "Verstuurd: \(sent) mails.")
            if failed > 0 { s += " " + String(localized: "\(failed) mislukt.") }
            if let n = r.number { s += " " + String(localized: "Antwoorden komen in de inbox als ticket #\(n).") }
            result = s
            if sent > 0 { draft.clear() }
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch { self.error = error.mailText }
    }
}
