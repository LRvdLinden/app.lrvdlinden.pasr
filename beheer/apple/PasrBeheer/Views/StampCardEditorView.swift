import PhotosUI
import SwiftUI

/// Stempelkaart aanmaken of bewerken voor elke zaak (zakelijk 1.1; zelfde als de kaarteditor in beheer.pasr.nl):
/// live voorbeeld zoals op pasr.nl/zakelijk, "Huisstijl ophalen" (zelfde code als business-brand), QR-code en link,
/// flyer, publiceren of offline halen, verwijderen en een testklant voor de App Review.
struct StampCardEditorView: View {
    let business: Business
    let card: BusinessCard?
    var onChanged: () -> Void = {}
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    @State private var saved: BusinessCard?
    @State private var name = ""
    @State private var reward = ""
    @State private var total = 10
    @State private var color = "#6A5CFF"
    @State private var ink = ""          // "" = automatisch, "#FFFFFF" of "#000000"
    @State private var logo: String?
    @State private var logoChanged = false
    @State private var published = false
    @State private var site = ""
    @State private var brandMessage: String?
    @State private var fetching = false
    @State private var swatches: [String] = []
    @State private var demo = 0          // 0 leeg, 1 half vol, 2 vol
    @State private var photo: PhotosPickerItem?
    @State private var busy = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var confirmTest: (TestMember, Bool)?   // (lid, verwijderen?)

    private static let palette = ["#6A5CFF", "#17162A", "#E30613", "#FF6B57", "#E2683C", "#F2B705", "#2ED3A6", "#12A77E", "#0A84FF", "#7B4B2A", "#AF52DE", "#FF375F"]
    private var current: BusinessCard? { saved ?? card }
    private var approved: Bool { business.status == "approved" }
    private var swatchList: [String] {
        var seen = Set<String>(), out: [String] = []
        for h in swatches + Self.palette where !seen.contains(h) { seen.insert(h); out.append(h) }
        return out
    }
    private var count: Int { demo == 2 ? total : demo == 1 ? (total + 1) / 2 : 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StampCardPreview(name: name, business: business.name, city: business.city, logo: logo, color: color,
                                     textColor: ink.isEmpty ? nil : ink, total: total, count: count, reward: reward)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    Picker("Voorbeeld", selection: $demo) {
                        Text("Leeg").tag(0); Text("Half vol").tag(1); Text("Vol").tag(2)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Zo ziet de klant de kaart in Pasr en in de browser.")
                }
                .listRowBackground(Color.clear)

                if let message { Text(message).font(.subheadline).foregroundStyle(Theme.coral) }

                Section("Kaart") {
                    TextField("Naam van de kaart", text: $name)
                    TextField("Beloning", text: $reward)
                    Stepper(value: $total, in: 2...30) { LabeledContent("Aantal stempels", value: "\(total)") }
                }

                Section {
                    HStack {
                        TextField("Website", text: $site)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            #endif
                        Button { Task { await fetchBrand(auto: false) } } label: {
                            if fetching { ProgressView() } else { Text("Huisstijl ophalen") }
                        }
                        .buttonStyle(.bordered)
                        .disabled(fetching || site.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ColorPicker("Kleur", selection: Binding(get: { Color(hexString: color) }, set: { color = $0.hexString }), supportsOpacity: false)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(swatchList, id: \.self) { hex in
                                Button { color = hex } label: {
                                    Circle().fill(Color(hexString: hex)).frame(width: 26, height: 26)
                                        .overlay(Circle().stroke(color == hex ? Color.white : Color.white.opacity(0.25), lineWidth: color == hex ? 2.5 : 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(hex))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Picker("Tekstkleur", selection: $ink) {
                        Text("Automatisch").tag(""); Text("Wit").tag("#FFFFFF"); Text("Zwart").tag("#000000")
                    }
                    HStack {
                        PhotosPicker(selection: $photo, matching: .images) { Label("Kies logo", systemImage: "photo") }
                        Spacer()
                        if logo != nil { Button("Geen logo", role: .destructive) { logo = nil; logoChanged = true } }
                    }
                } header: {
                    Text("Huisstijl")
                } footer: {
                    if let brandMessage { Text(brandMessage) }
                }

                Section {
                    Toggle(approved ? "Online: klanten kunnen aansluiten" : "Online (kan na goedkeuring van de zaak)", isOn: $published)
                        .disabled(!approved)
                    Button { Task { await save() } } label: {
                        HStack { Text(current == nil ? "Kaart aanmaken" : "Opslaan"); if busy { Spacer(); ProgressView() } }
                    }
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty || reward.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let c = current {
                        if approved {
                            Button(c.published == true ? "Offline halen" : "Publiceren") { Task { await publish(!(c.published == true)) } }
                                .disabled(busy)
                        }
                        Button("Verwijderen", role: .destructive) { confirmDelete = true }.disabled(busy)
                    }
                }

                if let c = current {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            QRView(text: c.joinLink, size: 120)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(c.joinLink).font(.caption.monospaced()).textSelection(.enabled)
                                HStack {
                                    Button("Kopieer link", systemImage: "doc.on.doc") { Clipboard.copy(c.joinLink) }
                                    if let file = QRCode.pngFile(c.joinLink, name: "qr-" + c.name) { ShareLink("QR", item: file) }
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                                if let flyer = URL(string: c.flyerLink) { Link(destination: flyer) { Label("Flyer (A4)", systemImage: "printer") } }
                            }
                        }
                    } header: {
                        Text("QR-code en link")
                    } footer: {
                        Text(c.published == true ? "Hang de QR-code bij de kassa of deel de link. De flyer is een A4 om te printen."
                             : "De kaart is nog een concept: link, QR-code en flyer werken zodra hij online staat.")
                    }

                    Section {
                        ForEach(c.test_members ?? []) { m in TestMemberRow(member: m, card: c, business: business) { del in confirmTest = (m, del) } }
                        Button { Task { await makeTestMember() } } label: { Label("Testklant maken", systemImage: "person.crop.circle.badge.plus") }
                            .disabled(busy)
                    } header: {
                        Text("Testklant (App Review)")
                    } footer: {
                        Text("Een lid voor de review van Pasr Zakelijk door Apple: de reviewer scant de QR-code of typt de klantcode in de app.")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle(current == nil ? "Nieuwe stempelkaart" : "Stempelkaart bewerken")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
            .onAppear(perform: fill)
            .onChange(of: photo) { _, item in Task { await loadPhoto(item) } }
            .confirmationDialog("Stempelkaart verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Verwijderen", role: .destructive) { Task { await delete() } }
            } message: {
                Text("De kaart en alle leden met hun stempels gaan weg. Dit kan niet ongedaan worden gemaakt. De log blijft.")
            }
            .confirmationDialog(confirmTest?.1 == true ? "Testklant verwijderen?" : "Testklant resetten?",
                                isPresented: Binding(get: { confirmTest != nil }, set: { if !$0 { confirmTest = nil } }),
                                titleVisibility: .visible, presenting: confirmTest) { t in
                Button(t.1 ? "Verwijderen" : "Resetten", role: t.1 ? .destructive : nil) { Task { await testAction(t.0, delete: t.1) } }
            } message: { t in
                Text(t.1 ? "De klantcode werkt daarna niet meer." : "Stempels en beloningen van deze testklant gaan terug naar 0.")
            }
        }
    }

    private func fill() {
        site = business.website ?? ""
        guard let c = card else {
            // nieuwe kaart: huisstijl van de website meteen ophalen (zoals Pasr Zakelijk en het dashboard)
            if !site.isEmpty { Task { await fetchBrand(auto: true) } }
            return
        }
        name = c.name; reward = c.reward; total = c.stamps_total; color = c.color.uppercased(); logo = c.logo
        ink = ["#FFFFFF", "#000000"].contains(c.text_color?.uppercased() ?? "") ? c.text_color!.uppercased() : ""
        published = c.published == true && approved
    }

    private func fetchBrand(auto: Bool) async {
        fetching = true
        defer { fetching = false }
        var p: [String: Any] = ["business_id": business.id]
        let norm = { (s: String) in s.lowercased().replacingOccurrences(of: "^https?://", with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
        if norm(site) != norm(business.website ?? "") { p["url"] = site.trimmingCharacters(in: .whitespaces) }
        do {
            let r = try await session.call("business_brand", p, as: BrandResponse.self)
            if let l = r.logo { logo = l; logoChanged = true }
            if let c = r.color {
                color = c.uppercased()
                swatches = [c.uppercased()] + swatches.filter { $0 != c.uppercased() }
                if let t = r.text_color?.uppercased() { ink = t }
            }
            brandMessage = String(format: String(localized: "Overgenomen van %@. Pas gerust aan."), r.domain ?? site)
        } catch {
            brandMessage = auto ? String(localized: "Geen huisstijl gevonden; kies zelf een kleur en logo.") : error.localizedDescription
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let png = LogoColor.pngForUpload(data), png.count < 150_000 else { message = String(localized: "Dit logo is te groot of onbruikbaar."); return }
        logo = png.base64EncodedString()
        logoChanged = true
        if let c = LogoColor.average(png) { swatches = [c] + swatches.filter { $0 != c } }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        var c: [String: Any] = ["name": name.trimmingCharacters(in: .whitespaces), "reward": reward.trimmingCharacters(in: .whitespaces),
                                "stamps_total": total, "color": color, "text_color": ink, "published": published && approved]
        if let id = current?.id { c["id"] = id }
        if current == nil || logoChanged { c["logo"] = logo ?? NSNull() }
        do {
            saved = try await session.call("business_card_save", ["business_id": business.id, "card": c], as: BusinessCardResponse.self).card
            logoChanged = false
            message = nil
            onChanged()
        } catch { message = error.localizedDescription }
    }

    private func publish(_ on: Bool) async {
        guard let c = current else { return }
        busy = true
        defer { busy = false }
        do {
            saved = try await session.call("business_card_publish", ["id": c.id, "published": on], as: BusinessCardResponse.self).card
            published = on
            onChanged()
        } catch { message = error.localizedDescription }
    }

    private func delete() async {
        guard let c = current else { return }
        do {
            _ = try await session.call("business_card_delete", ["id": c.id], as: BusinessCardDeleteResponse.self)
            onChanged()
            dismiss()
        } catch { message = error.localizedDescription }
    }

    private func makeTestMember() async {
        guard var c = current else { return }
        busy = true
        defer { busy = false }
        do {
            let m = try await session.call("business_test_member", ["card_id": c.id], as: TestMemberResponse.self).member
            c.test_members = (c.test_members ?? []) + [m]
            saved = c
            if c.published != true { message = String(localized: "Testklant gemaakt. Zet de kaart online, anders kan de reviewer niet scannen.") }
            onChanged()
        } catch { message = error.localizedDescription }
    }

    private func testAction(_ m: TestMember, delete: Bool) async {
        guard var c = current else { return }
        do {
            try await session.call(delete ? "business_test_member_delete" : "business_test_member_reset", ["id": m.id])
            c.test_members = delete ? (c.test_members ?? []).filter { $0.id != m.id }
                : (c.test_members ?? []).map { $0.id == m.id ? TestMember(id: $0.id, member_code: $0.member_code, label: $0.label, stamps_count: 0, rewards_redeemed: 0) : $0 }
            saved = c
            onChanged()
        } catch { message = error.localizedDescription }
    }
}

/// Testklant: de klantcode als tekst en als grote QR-code, met PNG delen/bewaren, afdrukken, resetten en verwijderen.
private struct TestMemberRow: View {
    let member: TestMember
    let card: BusinessCard
    let business: Business
    var onAction: (Bool) -> Void

    var body: some View {
        VStack(spacing: 10) {
            QRView(text: member.member_code, size: 220)
            Text(member.label ?? String(localized: "Testklant (App Review)")).font(.caption).foregroundStyle(Theme.muted)
            Text(member.spaced).font(.title3.monospaced().weight(.bold)).textSelection(.enabled)
            Text("\(member.stamps_count) van \(card.stamps_total) stempels").font(.caption).foregroundStyle(Theme.muted)
            ViewThatFits {
                HStack { buttons }
                VStack { buttons }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var buttons: some View {
        if let file = QRCode.pngFile(member.member_code, name: "testklant-" + member.member_code) {
            ShareLink(item: file) { Label("PNG", systemImage: "square.and.arrow.up") }
        }
        Button("Afdrukken", systemImage: "printer") {
            QRPrint.print(member.member_code, title: "\(business.name) · \(card.name)", caption: member.spaced)
        }
        Button("Kopieer code", systemImage: "doc.on.doc") { Clipboard.copy(member.member_code) }
        Button("Resetten", systemImage: "arrow.counterclockwise") { onAction(false) }
        Button("Verwijderen", systemImage: "trash", role: .destructive) { onAction(true) }
    }
}
