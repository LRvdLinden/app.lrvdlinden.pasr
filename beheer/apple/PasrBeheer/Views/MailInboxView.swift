import SwiftUI
import QuickLook

// MARK: - Inbox: tickets uit mail (`mail_thread_list`, `mail_thread_get`, `mail_thread_reply`, `mail_thread_note`, `mail_thread_status`)

struct MailBrandBadge: View {
    let brand: String?
    var body: some View {
        let zakelijk = brand == "zakelijk"
        Text(verbatim: zakelijk ? "Pasr Zakelijk" : "Pasr")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill((zakelijk ? Theme.mint : Theme.iris).opacity(0.22)))
            .foregroundStyle(zakelijk ? Theme.mint : Theme.iris2)
    }
}

struct MailStatusBadge: View {
    let status: String?
    var body: some View {
        let color: Color = {
            switch status {
            case "new": return Theme.coral
            case "open": return Theme.sky
            case "pending": return Theme.amber
            default: return Theme.muted
            }
        }()
        Text(verbatim: MailLabels.status(status))
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }
}

struct MailInboxView: View {
    let status: MailStatus?
    let reloadStatus: () async -> Void

    @EnvironmentObject private var session: Session
    @State private var filter = "active"
    @State private var brandFilter = ""
    @State private var query = ""
    @State private var items: [MailThread] = []
    @State private var total = 0
    @State private var page = 0
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    @State private var counts: MailCounts?
    @State private var polling = false
    @State private var pollResult: String?

    private let pageSize = 30

    var body: some View {
        List {
            Section {
                statusCard
                filterBar
                Picker("Merk", selection: $brandFilter) {
                    Text("Alle merken").tag("")
                    Text(verbatim: "Pasr").tag("pasr")
                    Text(verbatim: "Pasr Zakelijk").tag("zakelijk")
                }
                .pickerStyle(.menu)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                if let error { Text(error).foregroundStyle(Theme.coral) }
                ForEach(items) { t in
                    NavigationLink(value: t.number) { MailThreadRow(thread: t) }
                        .listRowBackground(Theme.card)
                        .onAppear { if t.id == items.last?.id { Task { await loadMore() } } }
                }
                if loaded && items.isEmpty && error == nil {
                    Text(LocalizedStringKey(!query.trimmingCharacters(in: .whitespaces).isEmpty ? "Geen mails gevonden."
                         : filter == "active" ? "Geen openstaande mails." : "Geen mails."))
                        .foregroundStyle(Theme.muted).listRowBackground(Theme.card)
                }
                if loading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
            } footer: {
                if loaded && total > 0 {
                    (total == 1 ? Text("1 mail") : Text("\(total) mails")).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .searchable(text: $query, prompt: "Zoek op #nummer, onderwerp, naam of adres")
        .autocorrectionDisabled()
        .navigationDestination(for: Int.self) { n in
            MailThreadView(number: n) { await reloadAll() }
        }
        .refreshable { await reloadAll() }
        .task(id: "\(filter)|\(brandFilter)|\(query)|\(session.refreshTick)") {
            if loaded { try? await Task.sleep(for: .milliseconds(300)) }
            if Task.isCancelled { return }
            await reloadAll()
        }
    }

    // MARK: onderdelen

    @ViewBuilder private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if status?.smtp == false {
                Label("E-mail versturen is nog niet ingesteld (PASR_SMTP_*): antwoorden worden opgeslagen maar niet verstuurd.", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(Theme.amber)
            }
            if status?.imap == false {
                Label("De inbox (IMAP) is nog niet ingesteld (PASR_IMAP_*): mails komen niet automatisch binnen.", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(Theme.amber)
            } else if let s = status?.sync {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inbox: laatst opgehaald \(Fmt.ago(s.last_run)) · \(s.imported ?? 0) geïmporteerd van \(s.fetched ?? 0)")
                        .font(.caption).foregroundStyle(Theme.muted)
                    if let e = s.last_error, !e.isEmpty {
                        Text(verbatim: e).font(.caption).foregroundStyle(Theme.coral).lineLimit(3)
                    }
                }
            }
            HStack {
                Button { Task { await poll() } } label: {
                    HStack(spacing: 6) { if polling { ProgressView().controlSize(.small) }; Text(LocalizedStringKey(polling ? "Ophalen…" : "Nu ophalen")) }
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(polling || status?.imap == false)
                Spacer()
            }
            if let pollResult { Text(pollResult).font(.caption).foregroundStyle(Theme.mint) }
        }
        .padding(.vertical, 4)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MailLabels.filters, id: \.key) { f in
                    let on = f.key == filter
                    Button { filter = f.key } label: {
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey(f.label))
                            if let n = (counts ?? status?.counts)?.count(for: f.key) {
                                Text(Fmt.n(n)).font(.caption.weight(.bold)).padding(.horizontal, 6)
                                    .background(Capsule().fill(on ? Color.white.opacity(0.25) : Color.white.opacity(0.1)))
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(on ? Color.white : Theme.muted)
                        .background(Capsule().fill(on ? Theme.iris : Theme.card2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    // MARK: laden

    private func reloadAll() async {
        async let s: Void = reloadStatus()
        await fetch(page: 0, replace: true)
        await s
    }

    private func loadMore() async {
        guard !loading, items.count < total else { return }
        await fetch(page: page + 1, replace: false)
    }

    private func fetch(page p: Int, replace: Bool) async {
        loading = true
        defer { loading = false }
        var params: [String: Any] = ["status": filter, "q": query.trimmingCharacters(in: .whitespaces), "page": p, "page_size": pageSize]
        if !brandFilter.isEmpty { params["brand"] = brandFilter }
        do {
            let r = try await session.call("mail_thread_list", params, as: MailThreadList.self)
            total = r.total ?? r.items.count
            page = p
            if replace { items = r.items } else { items += r.items.filter { n in !items.contains { $0.number == n.number } } }
            if let c = r.counts { counts = c }
            error = nil
            loaded = true
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch {
            self.error = error.mailText
            if replace { items = [] }
            loaded = true
        }
    }

    /// "Nu ophalen": de inbox direct importeren (`mail_poll`).
    private func poll() async {
        polling = true; pollResult = nil
        defer { polling = false }
        do {
            let r = try await session.call("mail_poll", as: MailPollResponse.self)
            if r.skipped != nil {
                pollResult = String(localized: "IMAP is niet ingesteld.")
            } else if r.ok == false {
                pollResult = String(localized: "Ophalen mislukt.") + (r.error.map { " (\($0))" } ?? "")
            } else {
                let n = (r.new_threads ?? 0) + (r.replies ?? 0)
                pollResult = n > 0
                    ? String(localized: "\(n) mails verwerkt (\(r.new_threads ?? 0) nieuw, \(r.replies ?? 0) reacties).")
                    : String(localized: "Geen nieuwe mails (\(r.fetched ?? 0) bekeken).")
            }
        } catch is CancellationError {
        } catch { pollResult = error.mailText }
        await reloadAll()
    }
}

struct MailThreadRow: View {
    let thread: MailThread

    var body: some View {
        let t = thread
        let unread = t.unread == true
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if unread { Circle().fill(Theme.iris2).frame(width: 8, height: 8).accessibilityLabel("Ongelezen") }
                Text(verbatim: "#\(t.number)").font(.subheadline.weight(.bold)).monospacedDigit()
                    .foregroundStyle(unread ? Color.white : Theme.muted)
                MailBrandBadge(brand: t.brand)
                Spacer()
                MailStatusBadge(status: t.status)
            }
            Text(verbatim: t.subject ?? "").font(.body.weight(unread ? .bold : .semibold)).lineLimit(2)
            Text(verbatim: [t.contact_name, t.contact_email].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            if let p = t.preview, !p.isEmpty {
                Text(verbatim: p).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
            }
            Text(Fmt.ago(t.last_message_at)).font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Ticket

struct MailThreadView: View {
    let number: Int
    let onChange: () async -> Void

    @EnvironmentObject private var session: Session
    @State private var detail: MailThreadDetail?
    @State private var error: String?

    // antwoord of notitie
    @State private var kind = Kind.reply
    @State private var text = ""
    @State private var cc = ""
    @State private var bcc = ""
    @State private var attachments: [MailDraftAttachment] = []
    @State private var brand: MailBrand = .pasr
    @State private var after = "pending"
    @State private var sending = false
    @State private var confirming = false
    @State private var sendError: String?
    @State private var showPreview = false
    @State private var showHTML: MailMessage?

    // status
    @State private var status = "new"
    @State private var priority = "normal"
    @State private var saving = false

    // bijlagen openen
    @State private var files: [String: URL] = [:]
    @State private var loadingFile: String?
    @State private var quickLook: URL?

    enum Kind: String { case reply, note }

    private var ccList: MailAddressList { MailAddressList.parse(cc) }
    private var bccList: MailAddressList { MailAddressList.parse(bcc) }
    private var attBytes: Int { attachments.reduce(0) { $0 + $1.data.count } }

    var body: some View {
        Form {
            if let error, detail == nil {
                Section { Text(error).foregroundStyle(Theme.coral) }
            } else if detail == nil {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            }
            if let d = detail {
                header(d.thread)
                Section("Gesprek") {
                    if d.messages.isEmpty { Text("Geen berichten.").foregroundStyle(Theme.muted) }
                    ForEach(d.messages) { m in bubble(m) }
                }
                composer(d.thread)
                statusSection(d.thread)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("#\(number)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .refreshable { await load() }
        .task { if detail == nil { await load() } }
        .quickLookPreview($quickLook)
        .sheet(item: $showHTML) { m in
            NavigationStack {
                MailHTMLView(html: m.body_html ?? "", dark: false)
                    .background(Color.white)
                    .navigationTitle("Opgemaakt")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Sluiten") { showHTML = nil } } }
            }
            .frame(minWidth: 420, minHeight: 480)
        }
        .confirmationDialog("Antwoord versturen?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Versturen") { Task { await sendReply() } }
        } message: {
            Text(confirmMessage)
        }
    }

    // MARK: onderdelen

    private func header(_ t: MailThread) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: t.subject ?? "").font(.title3.weight(.bold))
                HStack(spacing: 8) {
                    MailBrandBadge(brand: t.brand)
                    MailStatusBadge(status: t.status)
                    Text("Aangemaakt \(Fmt.ago(t.created_at))").font(.caption).foregroundStyle(Theme.muted)
                }
                LabeledContent("Contact") {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let n = t.contact_name, !n.isEmpty { Text(verbatim: n) }
                        if let e = t.contact_email, !e.isEmpty {
                            if let u = URL(string: "mailto:\(e)") { Link(destination: u) { Text(verbatim: e) } } else { Text(verbatim: e) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func bubble(_ m: MailMessage) -> some View {
        let out = m.direction == "out", note = m.direction == "note"
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(LocalizedStringKey(note ? "Interne notitie" : out ? "Verstuurd" : "Ontvangen")).font(.caption.weight(.bold))
                    .foregroundStyle(note ? Theme.amber : out ? Theme.iris2 : Theme.mint)
                Text(Fmt.ago(m.created_at)).font(.caption2).foregroundStyle(Theme.muted)
                Spacer()
                if (m.body_html ?? "").isEmpty == false {
                    Button("Opgemaakt") { showHTML = m }.font(.caption).buttonStyle(.borderless)
                }
            }
            if let f = m.from, !f.isEmpty, !note {
                Text(verbatim: f).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            if out {
                let n = (m.to?.count ?? 0), c = (m.cc?.count ?? 0), b = (m.bcc_count ?? 0)
                Text("Aan \(n) · cc \(c) · bcc \(b)").font(.caption).foregroundStyle(Theme.muted)
            }
            Text(verbatim: m.body_text ?? "").font(.subheadline).textSelection(.enabled)
            if let e = m.error, !e.isEmpty {
                Text(verbatim: e).font(.caption).foregroundStyle(Theme.coral)
            }
            ForEach(m.attachments ?? []) { a in attachmentRow(a) }
        }
        .padding(.vertical, 4)
    }

    private func attachmentRow(_ a: MailAttachment) -> some View {
        HStack {
            Button { Task { await openAttachment(a) } } label: {
                HStack(spacing: 6) {
                    if loadingFile == a.id { ProgressView().controlSize(.small) } else { Image(systemName: "paperclip") }
                    Text(verbatim: a.name).lineLimit(1)
                    if let s = a.size { Text(verbatim: MailAttachmentsRows.size(s)).foregroundStyle(Theme.muted) }
                }
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(loadingFile != nil)
            Spacer()
            if let url = files[a.id] {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless)
            }
        }
    }

    private func composer(_ t: MailThread) -> some View {
        Section {
            Picker("Soort bericht", selection: $kind) {
                Text("Antwoord aan klant").tag(Kind.reply)
                Text("Interne notitie").tag(Kind.note)
            }
            .pickerStyle(.segmented)

            if kind == .reply {
                Picker("Merk", selection: $brand) {
                    ForEach(MailBrand.allCases) { Text(verbatim: $0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                MailAddressField(title: "CC", prompt: "Extra adressen (komma, spatie of regel)", text: $cc)
                MailAddressField(title: "BCC", prompt: "Verborgen adressen (komma, spatie of regel)", text: $bcc)
                MailBodyEditor(text: $text)
                MailAttachmentsRows(attachments: $attachments)
                Toggle("Voorbeeld tonen", isOn: $showPreview)
                if showPreview {
                    MailPreviewSection(markdown: text, brand: brand, subject: t.subject ?? "")
                }
                Picker("Status na verzenden", selection: $after) {
                    Text("Wacht op reactie").tag("pending")
                    Text("Open").tag("open")
                    Text("Gesloten").tag("closed")
                }
            } else {
                TextField("Alleen zichtbaar in het beheer…", text: $text, axis: .vertical).lineLimit(4...12)
            }

            Button {
                if kind == .reply { confirming = true } else { Task { await saveNote() } }
            } label: {
                HStack { Spacer(); if sending { ProgressView() } else { Label(LocalizedStringKey(kind == .reply ? "Antwoord versturen" : "Notitie opslaan"), systemImage: kind == .reply ? "paperplane.fill" : "note.text").bold() }; Spacer() }
            }
            .disabled(sending || !canSend)
            if let sendError { Text(sendError).font(.subheadline).foregroundStyle(Theme.coral) }
        } header: { Text(LocalizedStringKey(kind == .reply ? "Antwoord" : "Notitie")) } footer: {
            if kind == .reply {
                Text("De klant krijgt een mail met #\(t.number) in het onderwerp; antwoorden komen weer in dit ticket.")
            }
        }
    }

    private var confirmMessage: String {
        var s = String(localized: "Het antwoord gaat per mail als \(brand.title) naar de klant")
        if !ccList.valid.isEmpty { s += String(localized: " en \(ccList.valid.count) cc") }
        if !bccList.valid.isEmpty { s += String(localized: " en \(bccList.valid.count) bcc") }
        return s + String(localized: ". Dit kan niet worden teruggedraaid.")
    }

    private var canSend: Bool {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if kind == .note { return true }
        return ccList.invalid.isEmpty && bccList.invalid.isEmpty && attBytes <= MailLimits.attachmentBytes
            && ccList.valid.count + bccList.valid.count + 1 <= MailLimits.recipients
    }

    private func statusSection(_ t: MailThread) -> some View {
        Section("Status") {
            Picker("Status", selection: $status) {
                ForEach(MailLabels.statuses, id: \.key) { Text(LocalizedStringKey($0.label)).tag($0.key) }
            }
            Picker("Prioriteit", selection: $priority) {
                ForEach(MailLabels.priorities, id: \.key) { Text(LocalizedStringKey($0.label)).tag($0.key) }
            }
            Button {
                Task { await saveStatus(t) }
            } label: { HStack { if saving { ProgressView() }; Text("Opslaan") } }
            .disabled(saving || (status == (t.status ?? "new") && priority == (t.priority ?? "normal")))
        }
    }

    // MARK: acties

    private func load() async {
        do {
            let d = try await session.call("mail_thread_get", ["number": number], as: MailThreadDetail.self)
            detail = d
            status = d.thread.status ?? "new"
            priority = d.thread.priority ?? "normal"
            if let b = d.thread.brand.flatMap(MailBrand.init(rawValue:)), detail != nil, text.isEmpty { brand = b }
            error = nil
            await onChange()
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch { self.error = error.mailText }
    }

    private func sendReply() async {
        guard !sending else { return }
        sending = true; sendError = nil
        defer { sending = false }
        var p: [String: Any] = ["number": number, "body_md": text.trimmingCharacters(in: .whitespacesAndNewlines),
                                "brand": brand.rawValue, "status": after]
        if !ccList.valid.isEmpty { p["cc"] = ccList.valid }
        if !bccList.valid.isEmpty { p["bcc"] = bccList.valid }
        if !attachments.isEmpty { p["attachments"] = attachments.map { $0.json } }
        do {
            let r = try await session.call("mail_thread_reply", p, as: MailReplyResponse.self, timeout: 120)
            if r.email_sent == false {
                sendError = String(localized: "Het antwoord is opgeslagen, maar de mail is niet verstuurd.")
            }
            text = ""; cc = ""; bcc = ""; attachments = []
            await load()
        } catch is CancellationError {
        } catch { sendError = error.mailText }
    }

    private func saveNote() async {
        guard !sending else { return }
        sending = true; sendError = nil
        defer { sending = false }
        do {
            try await session.call("mail_thread_note", ["number": number, "text": text.trimmingCharacters(in: .whitespacesAndNewlines)])
            text = ""
            await load()
        } catch is CancellationError {
        } catch { sendError = error.mailText }
    }

    private func saveStatus(_ t: MailThread) async {
        saving = true
        defer { saving = false }
        var p: [String: Any] = ["number": number]
        if status != (t.status ?? "new") { p["status"] = status }
        if priority != (t.priority ?? "normal") { p["priority"] = priority }
        do {
            try await session.call("mail_thread_status", p)
            await load()
        } catch is CancellationError {
        } catch { sendError = error.mailText }
    }

    /// Bijlage ophalen (`mail_attachment`), tijdelijk bewaren en openen; daarna ook te delen.
    private func openAttachment(_ a: MailAttachment) async {
        if let url = files[a.id] { quickLook = url; return }
        loadingFile = a.id
        defer { loadingFile = nil }
        do {
            let r = try await session.call("mail_attachment", ["id": a.id], as: MailAttachmentData.self, timeout: 120)
            guard let b64 = r.data_b64, let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else {
                sendError = String(localized: "Deze bijlage kan niet worden geopend."); return
            }
            let safe = (r.name ?? a.name).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PasrMail", isDirectory: true)
                .appendingPathComponent(a.id, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(safe.isEmpty ? "bijlage" : safe)
            try data.write(to: url, options: .atomic)
            files[a.id] = url
            quickLook = url
        } catch is CancellationError {
        } catch { sendError = error.mailText }
    }
}
