import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Winkels: aanvragen uit de app (gebundeld per winkel), een kaart maken met logo en merkkleur en die publiceren.
/// Gepubliceerde winkels staan meteen in Pasr, zonder app-update; de aanvragers krijgen een pushmelding.
struct StoresView: View {
    @EnvironmentObject private var session: Session
    enum Filter: String, CaseIterable, Identifiable {
        case open, stores, rejected, balance
        var id: String { rawValue }
        var title: String {
            switch self {
            case .open: "Open"
            case .stores: "Toegevoegd"
            case .rejected: "Afgewezen"
            case .balance: "Saldo"
            }
        }
    }
    @State private var filter: Filter = .open
    @State private var groups: [StoreRequestGroup] = []
    @State private var stores: [RemoteStore] = []
    @State private var error: String?
    @State private var loading = false
    @State private var editing: StoreDraft?
    @State private var pages: [BalancePage] = []
    @State private var newStore = ""
    @State private var newURL = ""

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Aanvragen komen uit de app (alleen met een account). Publiceer je een winkel, dan staat hij meteen in Pasr en krijgen de aanvragers een pushmelding.")
            }
            if let error {
                Text(error).foregroundStyle(Theme.coral).font(.subheadline)
            }
            if filter == .balance {
                let filled = Dictionary(uniqueKeysWithValues: pages.map { ($0.store_id, $0.url) })
                Section {
                    ForEach(VoucherStores.all, id: \.id) { store in
                        BalancePageRow(storeID: store.id, name: store.name, url: filled[store.id] ?? "") { await load() }
                    }
                } header: {
                    Text("Cadeaukaarten in de app")
                } footer: {
                    Text("\(VoucherStores.all.filter { filled[$0.id] == nil }.count) van \(VoucherStores.all.count) hebben nog geen saldo-pagina. De knop Saldo checken in de app opent dit adres, met het kaartnummer klaar om te plakken.")
                }
                let others = pages.filter { p in !VoucherStores.all.contains { $0.id == p.store_id } }
                Section {
                    ForEach(others) { p in
                        BalancePageRow(storeID: p.store_id, name: p.store_id, url: p.url) { await load() }
                    }
                    TextField("Andere winkel: winkel-id, bijv. kwantum", text: $newStore)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("https://…", text: $newURL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                    Button("Opslaan") { Task { await savePage() } }
                        .disabled(newStore.isEmpty || newURL.isEmpty)
                } header: {
                    Text("Andere winkels")
                }
            } else if filter == .stores {
                if stores.isEmpty && !loading { Text("Nog geen winkels toegevoegd via het beheer.").foregroundStyle(Theme.muted) }
                ForEach(stores) { s in
                    Button { editing = StoreDraft(store: s) } label: { storeRow(s) }
                        .buttonStyle(.plain)
                }
            } else {
                if groups.isEmpty && !loading {
                    Text(filter == .open ? "Geen open aanvragen. Mooi zo." : "Niets afgewezen.").foregroundStyle(Theme.muted)
                }
                ForEach(groups) { g in
                    Button {
                        if filter == .open { editing = StoreDraft(request: g) }
                    } label: { requestRow(g) }
                        .buttonStyle(.plain)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Winkels")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = StoreDraft() } label: { Label("Nieuwe winkel", systemImage: "plus") }
            }
        }
        .refreshable { await load() }
        .task(id: "\(filter.rawValue)|\(session.refreshTick)") { await load() }
        .sheet(item: $editing) { draft in
            StoreEditorView(draft: draft) { Task { await load() } }
                .environmentObject(session)
        }
    }

    private func requestRow(_ g: StoreRequestGroup) -> some View {
        HStack(spacing: 12) {
            Text("\(g.count)")
                .font(.headline.monospacedDigit())
                .frame(width: 38, height: 38)
                .background(Theme.amber.opacity(0.18), in: Circle())
                .foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text(g.name).font(.body.weight(.semibold))
                Text([g.kind == "voucher" ? "Cadeaukaart / voucher" : nil, g.website, Fmt.plural(g.count, "aanvraag", "aanvragen"),
                      "laatste " + Fmt.ago(g.last)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.muted)
                if let note = g.notes.first {
                    Text("“\(note)”").font(.caption).italic().foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
            Spacer()
            if filter == .open { Image(systemName: "chevron.right").foregroundStyle(Theme.muted) }
        }
        .contentShape(Rectangle())
    }

    private func storeRow(_ s: RemoteStore) -> some View {
        HStack(spacing: 12) {
            LogoTile(hex: s.card_hex, logo: s.logo, name: s.name)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name).font(.body.weight(.semibold))
                Text([s.published ? "Gepubliceerd" : "Concept", s.domain, s.category].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(s.published ? Theme.mint : Theme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
        }
        .contentShape(Rectangle())
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            if filter == .balance {
                pages = try await session.call("balance_pages", as: BalancePagesResponse.self).pages
            } else if filter == .stores {
                stores = try await session.call("stores", as: StoresResponse.self).stores
            } else {
                groups = try await session.call("store_requests", ["status": filter.rawValue], as: StoreRequestsResponse.self).groups
            }
            error = nil
        } catch is CancellationError {
        } catch let e as APIError where e.isUnauthorized {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension StoresView {
    fileprivate func savePage() async {
        var url = newURL.trimmingCharacters(in: .whitespaces)
        if !url.lowercased().hasPrefix("http") { url = "https://" + url }
        do {
            try await session.call("balance_page_save", ["store_id": newStore.trimmingCharacters(in: .whitespaces).lowercased(), "url": url])
            newStore = ""
            newURL = ""
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    fileprivate func deletePage(_ p: BalancePage) async {
        do {
            try await session.call("balance_page_delete", ["store_id": p.store_id])
            pages.removeAll { $0.store_id == p.store_id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Eén winkel met zijn saldo-pagina: invullen, opslaan, opzoeken of wissen.
struct BalancePageRow: View {
    @EnvironmentObject private var session: Session
    let storeID: String
    let name: String
    let url: String
    var onChange: () async -> Void
    @State private var text = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: url.isEmpty ? "eurosign.circle" : "checkmark.circle.fill")
                    .foregroundStyle(url.isEmpty ? Theme.muted : Theme.mint)
                Text(name).font(.body.weight(.semibold))
                Spacer()
                if let search = URL(string: "https://www.google.com/search?q=" + (name + " saldo checken").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) {
                    Link("Zoek", destination: search).font(.footnote)
                }
            }
            HStack {
                TextField("https://… (saldo-pagina)", text: $text)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { Task { await save() } }
                if busy { ProgressView() } else if text != url && !text.isEmpty {
                    Button("Opslaan") { Task { await save() } }.buttonStyle(.borderless)
                }
            }
            .font(.subheadline)
            if let message { Text(message).font(.caption).foregroundStyle(Theme.coral) }
        }
        .onAppear { text = url }
        .onChange(of: url) { _, new in text = new }
        .swipeActions {
            if !url.isEmpty {
                Button(role: .destructive) { Task { await clear() } } label: { Label("Wis", systemImage: "trash") }
            }
        }
    }

    private func save() async {
        var value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        if !value.lowercased().hasPrefix("http") { value = "https://" + value }
        busy = true
        defer { busy = false }
        do {
            try await session.call("balance_page_save", ["store_id": storeID, "url": value])
            message = nil
            await onChange()
        } catch {
            message = error.localizedDescription
        }
    }

    private func clear() async {
        do {
            try await session.call("balance_page_delete", ["store_id": storeID])
            await onChange()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct BalancePage: Decodable, Identifiable, Hashable {
    let store_id: String
    let url: String
    var id: String { store_id }
}

struct BalancePagesResponse: Decodable { let pages: [BalancePage] }

/// Wat het formulier bewerkt.
struct StoreDraft: Identifiable {
    var id = UUID()
    var storeID: String?
    var name = ""
    var domain = ""
    var category = "Overig"
    var hex = "#2B2F3A"
    var format = "ean13"
    var kind = "loyalty"
    var aliases = ""
    var logo: String?
    var published = false
    var requestIDs: [String] = []
    var fromRequest = false

    init() {}
    init(request g: StoreRequestGroup) {
        name = g.name
        domain = g.website ?? ""
        if g.kind == "voucher" { kind = "voucher"; category = "Cadeaukaarten"; format = "code128" }
        requestIDs = g.ids
        fromRequest = true
    }
    init(store s: RemoteStore) {
        storeID = s.id; name = s.name; domain = s.domain; category = s.category; hex = s.card_hex
        format = s.format; kind = s.kind; aliases = s.aliases.joined(separator: ", "); logo = s.logo; published = s.published
    }
}

struct StoreEditorView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    @State var draft: StoreDraft
    var onDone: () -> Void
    @State private var swatches: [String] = []
    @State private var busy = false
    @State private var message: String?
    @State private var push = true
    @State private var photo: PhotosPickerItem?
    @State private var confirmPublish = false
    @State private var confirmReject = false

    static let categories = ["Supermarkt", "Drogist en beauty", "Warenhuis en wonen", "Mode en schoenen", "Elektronica",
                             "Doe-het-zelf en tuin", "Sport en vrije tijd", "Tanken en reizen", "Eten en drinken",
                             "Boeken en cadeaus", "Dieren", "Cadeaukaarten", "Overig"]
    static let formats: [(String, String)] = [("ean13", "EAN-13"), ("ean8", "EAN-8"), ("upcA", "UPC-A"), ("code128", "Code 128"),
                                               ("code39", "Code 39"), ("itf", "ITF"), ("qr", "QR"), ("pdf417", "PDF417"), ("aztec", "Aztec")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CardPreview(hex: draft.hex, logo: draft.logo, name: draft.name, voucher: draft.kind == "voucher")
                        .frame(maxWidth: 360)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                Section("Website") {
                    HStack {
                        TextField("winkel.nl", text: $draft.domain)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                        Button("Opzoeken") { Task { await lookup() } }
                            .disabled(busy || draft.domain.isEmpty)
                    }
                }
                Section("Kaart") {
                    TextField("Naam", text: $draft.name)
                    Picker("Categorie", selection: $draft.category) { ForEach(Self.categories, id: \.self) { Text($0) } }
                    Picker("Soort code", selection: $draft.format) { ForEach(Self.formats, id: \.0) { Text($0.1).tag($0.0) } }
                    Picker("Soort kaart", selection: $draft.kind) {
                        Text("Klantenkaart").tag("loyalty")
                        Text("Cadeaukaart").tag("voucher")
                    }
                    ColorPicker("Kaartkleur", selection: Binding(get: { Color(hexString: draft.hex) },
                                                                set: { draft.hex = $0.hexString }), supportsOpacity: false)
                    if !swatches.isEmpty {
                        HStack(spacing: 10) {
                            Text("Uit logo en website").font(.caption).foregroundStyle(Theme.muted)
                            ForEach(swatches, id: \.self) { hex in
                                Button { draft.hex = hex } label: {
                                    Circle().fill(Color(hexString: hex)).frame(width: 26, height: 26)
                                        .overlay(Circle().strokeBorder(.white.opacity(draft.hex == hex ? 0.9 : 0.25), lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    TextField("Andere namen (komma's)", text: $draft.aliases)
                }
                Section("Logo") {
                    PhotosPicker(selection: $photo, matching: .images) { Label("Kies logo", systemImage: "photo") }
                    if draft.logo != nil {
                        Button("Geen logo", role: .destructive) { draft.logo = nil }
                    }
                }
                Section {
                    if !draft.requestIDs.isEmpty {
                        Text("Na publiceren worden \(Fmt.plural(draft.requestIDs.count, "aanvraag", "aanvragen")) gesloten als toegevoegd.")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                    if !draft.published { Toggle("Pushmelding sturen", isOn: $push) }
                    Button(draft.published ? "Opslaan en bijwerken" : "Toevoegen en publiceren") {
                        if draft.published { Task { await save(publish: true) } } else { confirmPublish = true }
                    }
                    .disabled(busy || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Opslaan als concept") { Task { await save(publish: false) } }.disabled(busy)
                    if draft.fromRequest { Button("Aanvraag afwijzen", role: .destructive) { confirmReject = true } }
                    if draft.published { Button("Offline halen", role: .destructive) { Task { await unpublish() } } }
                } footer: {
                    if let message { Text(message) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(draft.storeID == nil ? "Nieuwe winkel" : draft.name)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Sluit") { dismiss() } } }
            .task { if draft.fromRequest, !draft.domain.isEmpty, draft.logo == nil { await lookup() } }
            .onChange(of: photo) { _, item in Task { await loadPhoto(item) } }
            .confirmationDialog("Winkel publiceren?", isPresented: $confirmPublish, titleVisibility: .visible) {
                Button("Publiceren") { Task { await save(publish: true) } }
            } message: {
                Text("\(draft.name) komt meteen in Pasr, zonder app-update." + (push ? " De aanvragers en wie 'Nieuwe winkels' aan heeft, krijgen een pushmelding." : ""))
            }
            .confirmationDialog("Aanvraag afwijzen?", isPresented: $confirmReject, titleVisibility: .visible) {
                Button("Afwijzen", role: .destructive) { Task { await reject() } }
            } message: {
                Text("In de app ziet de aanvrager 'Niet toegevoegd'.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 640)
        #endif
    }

    private func lookup() async {
        busy = true
        message = "Website opzoeken…"
        defer { busy = false }
        do {
            let r = try await session.call("store_lookup", ["url": draft.domain], as: StoreLookup.self)
            draft.domain = r.domain
            if draft.name.isEmpty, let n = r.name { draft.name = n }
            if let logo = r.logo { draft.logo = logo }
            let fromLogo = r.logo.flatMap { Data(base64Encoded: $0) }.flatMap(LogoColor.average)
            swatches = Array(([fromLogo].compactMap { $0 } + r.colors).prefix(6))
            if draft.hex == "#2B2F3A", let first = swatches.first { draft.hex = first }
            message = r.logo == nil ? "Geen bruikbaar logo gevonden; kies er zelf een." : "Logo en kleuren gevonden. Controleer de kaart."
        } catch {
            message = (error as? APIError)?.code == "not_found" ? "Deze website kon niet worden geopend." : error.localizedDescription
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let png = LogoColor.pngForUpload(data) else { message = "Dit logo kan niet worden gebruikt."; return }
        draft.logo = png.base64EncodedString()
        if let c = LogoColor.average(png) { swatches = [c] + swatches.filter { $0 != c } }
    }

    private func params() -> [String: Any] {
        var store: [String: Any] = [
            "name": draft.name.trimmingCharacters(in: .whitespaces), "domain": draft.domain, "category": draft.category,
            "card_hex": draft.hex, "format": draft.format, "kind": draft.kind,
            "aliases": draft.aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
        ]
        if let id = draft.storeID { store["id"] = id }
        store["logo"] = draft.logo ?? NSNull()
        return ["store": store]
    }

    private func save(publish: Bool) async {
        busy = true
        defer { busy = false }
        do {
            let saved = try await session.call("store_save", params(), as: StoreSaveResponse.self).store
            draft.storeID = saved.id
            if publish {
                let r = try await session.call("store_publish", ["id": saved.id, "request_ids": draft.requestIDs, "push": push && !draft.published],
                                               as: StorePublishResponse.self)
                message = r.push_ready == false ? "Gepubliceerd. Pushmeldingen staan nog uit (APNs-sleutel ontbreekt)."
                    : "Gepubliceerd: \(Fmt.plural(r.closed, "aanvraag", "aanvragen")) gesloten, \(Fmt.plural(r.sent, "melding", "meldingen")) verstuurd."
                onDone()
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            } else {
                message = "Opgeslagen als concept."
                onDone()
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func reject() async {
        do {
            try await session.call("store_reject", ["request_ids": draft.requestIDs])
            onDone()
            dismiss()
        } catch { message = error.localizedDescription }
    }

    private func unpublish() async {
        guard let id = draft.storeID else { return }
        do {
            try await session.call("store_unpublish", ["id": id])
            onDone()
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

/// Voorbeeld van de kaart zoals hij in Pasr komt.
struct CardPreview: View {
    let hex: String
    let logo: String?
    let name: String
    var voucher = false

    var body: some View {
        let light = LogoColor.isLight(hex)
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(hexString: hex))
            .aspectRatio(1.586, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                Group {
                    if let image = logo.flatMap({ Data(base64Encoded: $0) }).flatMap(LogoColor.cgImage) {
                        Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxWidth: 170, maxHeight: 44, alignment: .leading)
                    } else {
                        Text(name.isEmpty ? "Winkel" : name).font(.title3.bold())
                    }
                }
                .padding(16)
            }
            .overlay(alignment: .bottomLeading) {
                Text(voucher ? "CADEAUKAART" : "KLANTENKAART").font(.caption2.weight(.bold)).opacity(0.75).padding(16)
            }
            .foregroundStyle(light ? Color(hex: 0x111216) : .white)
            .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
    }
}

/// Klein logo-blokje in een lijst.
struct LogoTile: View {
    let hex: String
    let logo: String?
    let name: String
    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color(hexString: hex))
            .frame(width: 54, height: 34)
            .overlay {
                if let image = logo.flatMap({ Data(base64Encoded: $0) }).flatMap(LogoColor.cgImage) {
                    Image(decorative: image, scale: 1).resizable().scaledToFit().padding(5)
                } else {
                    Text(String(name.prefix(1))).font(.caption.bold()).foregroundStyle(.white)
                }
            }
    }
}

/// Logo's lezen en de merkkleur eruit halen (zonder UIKit/AppKit, dus op iPhone, iPad en Mac gelijk).
enum LogoColor {
    static func cgImage(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Gemiddelde van de duidelijk gekleurde pixels (geen wit, zwart, grijs of doorzichtig).
    static func average(_ data: Data) -> String? {
        guard let image = cgImage(data) else { return nil }
        let n = 48
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        var r = 0, g = 0, b = 0, k = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            let R = Int(px[i]), G = Int(px[i + 1]), B = Int(px[i + 2]), A = Int(px[i + 3])
            let mx = max(R, G, B), mn = min(R, G, B)
            if A < 200 || (mx > 240 && mn > 240) || mx < 20 || mx - mn < 25 { continue }
            r += R; g += G; b += B; k += 1
        }
        guard k > 0 else { return nil }
        return String(format: "#%02X%02X%02X", r / k, g / k, b / k)
    }

    /// Klaar voor upload: hoogstens 512 px, als PNG, kleiner dan ~280 kB.
    static func pngForUpload(_ data: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        for side in [512, 384, 256] {
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: side,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
            guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            let out = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, thumb, nil)
            guard CGImageDestinationFinalize(dest) else { return nil }
            if out.length < 280_000 { return out as Data }
        }
        return nil
    }

    static func isLight(_ hex: String) -> Bool {
        let (r, g, b) = rgb(hex)
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b) > 0.45
    }

    static func rgb(_ hex: String) -> (Double, Double, Double) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return (0.17, 0.18, 0.23) }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}

extension Color {
    init(hexString: String) {
        let (r, g, b) = LogoColor.rgb(hexString)
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        let c = resolve(in: EnvironmentValues())
        return String(format: "#%02X%02X%02X", Int((max(0, min(1, c.red)) * 255).rounded()),
                      Int((max(0, min(1, c.green)) * 255).rounded()), Int((max(0, min(1, c.blue)) * 255).rounded()))
    }
}
