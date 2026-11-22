import SwiftUI
import PhotosUI
import CoreImage.CIFilterBuiltins

/// Kaarten van de zaak (eigenaar): maken, bewerken, publiceren, delen en flyer.
struct CardsView: View {
    let business: Business
    @Environment(BusinessStore.self) private var store
    @State private var editing: BusinessCard?
    @State private var sharing: BusinessCard?

    var body: some View {
        NavigationStack {
            List {
                if business.cards.isEmpty {
                    ContentUnavailableView {
                        Label("Nog geen stempelkaart", systemImage: "rectangle.stack.badge.plus")
                    } description: {
                        Text("Maak je eerste stempelkaart: kies een naam, kleur, aantal stempels en beloning.")
                    } actions: {
                        Button("Nieuwe kaart") { editing = BusinessCard() }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(business.cards) { card in
                    Section {
                        Button { editing = card } label: {
                            StampCardView(name: card.name, business: business.name, color: card.color, logo: card.logo,
                                          total: card.stampsTotal, filled: min(card.stampsTotal, max(1, card.stampsTotal / 2)), reward: card.reward,
                                          textColor: card.textColor)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        HStack(spacing: 14) {
                            Label(card.published ? "Online" : "Concept", systemImage: card.published ? "checkmark.seal.fill" : "pencil.circle")
                                .foregroundStyle(card.published ? Theme.mint : .secondary)
                            Spacer()
                            stat("person.2", card.members)
                            stat("seal", card.stamps)
                            stat("gift", card.rewards)
                        }
                        .font(.subheadline)
                        HStack {
                            Button("Bewerken", systemImage: "pencil") { editing = card }
                            Spacer()
                            if card.published {
                                Button("QR, link en flyer", systemImage: "qrcode") { sharing = card }
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Kaarten")
            .refreshable { await store.load() }
            .toolbar {
                BusinessPicker()
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = BusinessCard() } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("Nieuwe kaart"))
                        .disabled(business.cards.count >= 5)
                }
            }
            .sheet(item: $editing) { card in
                CardEditorView(business: business, card: card).trackModal()
            }
            .sheet(item: $sharing) { card in
                CardShareView(business: business, card: card).trackModal()
            }
        }
    }

    private func stat(_ icon: String, _ value: Int) -> some View {
        Label { Text(verbatim: "\(value)").monospacedDigit() } icon: { Image(systemName: icon) }
            .foregroundStyle(.secondary)
    }
}

/// Kaart maken of bewerken.
struct CardEditorView: View {
    let business: Business
    @State var card: BusinessCard
    @Environment(BusinessStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var logoChanged = false
    @State private var busy = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var saved = false
    @State private var brandBusy = false
    @State private var brandDomain: String?
    @State private var brandFailed = false

    private var isNew: Bool { card.id.isEmpty }
    private var valid: Bool {
        !card.name.trimmingCharacters(in: .whitespaces).isEmpty && !card.reward.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StampCardView(name: card.name.isEmpty ? String(localized: "Naam van de kaart") : card.name,
                                  business: business.name, color: card.color, logo: card.logo, total: card.stampsTotal,
                                  filled: max(1, card.stampsTotal * 6 / 10), reward: card.reward.isEmpty ? String(localized: "Je beloning") : card.reward,
                                  textColor: card.textColor)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                brandSection
                Section("Kaart") {
                    TextField("Naam (bijv. Koffiekaart)", text: $card.name)
                    TextField("Beloning (bijv. 1 gratis koffie)", text: $card.reward)
                    Stepper(value: $card.stampsTotal, in: 2...30) {
                        LabeledContent("Aantal stempels") { Text(verbatim: "\(card.stampsTotal)").monospacedDigit() }
                    }
                }
                Section("Kleur") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(Theme.swatches, id: \.self) { hex in
                            Button {
                                card.color = hex
                                card.textColor = nil
                            } label: {
                                Circle().fill(Color(hex: hex))
                                    .frame(height: 36)
                                    .overlay(Circle().strokeBorder(.primary, lineWidth: card.color.uppercased() == hex ? 3 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: hex))
                        }
                    }
                    .padding(.vertical, 4)
                    ColorPicker("Eigen kleur", selection: Binding(get: { Color(hex: card.color) }, set: { card.color = $0.hexString(); card.textColor = nil }),
                                supportsOpacity: false)
                }
                Section {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(card.logo == nil ? "Logo kiezen" : "Ander logo kiezen", systemImage: "photo")
                    }
                    if card.logo != nil {
                        Button("Logo weghalen", role: .destructive) {
                            card.logo = nil
                            logoChanged = true
                        }
                    }
                } header: {
                    Text("Logo")
                } footer: {
                    Text("Een vierkant logo werkt het best. Pasr verkleint het tot 256 pixels.")
                }
                Section {
                    Toggle("Online (klanten kunnen sparen)", isOn: $card.published)
                        .disabled(!business.isApproved)
                } footer: {
                    Text("Een concept zie je alleen zelf. Zet de kaart online om de QR-code en flyer te gebruiken.")
                }
                if let message {
                    Section { Text(message).foregroundStyle(Theme.coral) }
                }
                if !isNew {
                    Section {
                        Button("Kaart verwijderen", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Klanten met deze kaart kunnen dan niet meer sparen.")
                    }
                }
            }
            .navigationTitle(isNew ? "Nieuwe kaart" : "Kaart bewerken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button("Opslaan") { Task { await save() } }.disabled(!valid)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                       let encoded = LogoImage.encode(image) {
                        card.logo = encoded
                        logoChanged = true
                    } else {
                        message = String(localized: "Dit bestand is geen afbeelding.")
                    }
                }
            }
            .task {
                // nieuwe kaart: huisstijl van de website automatisch invullen
                if isNew && card.logo == nil && brandDomain == nil { await fetchBrand() }
            }
            .confirmationDialog("Kaart verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Verwijderen", role: .destructive) { Task { await delete() } }
                Button("Annuleer", role: .cancel) {}
            }
        }
    }

    @ViewBuilder private var brandSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: brandDomain != nil ? "wand.and.stars" : "paintpalette")
                    .foregroundStyle(brandDomain != nil ? Theme.mint : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    if brandBusy {
                        Text("Huisstijl ophalen…")
                    } else if let brandDomain {
                        Text(String(format: String(localized: "Overgenomen van %@"), brandDomain))
                    } else if brandFailed {
                        Text("Geen huisstijl gevonden. Kies zelf een logo en kleur.")
                    } else {
                        Text("Huisstijl van je website")
                    }
                }
                .font(.subheadline)
                Spacer()
                if brandBusy {
                    ProgressView()
                } else {
                    Button("Opnieuw ophalen") { Task { await fetchBrand() } }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
        } footer: {
            Text("Logo en kleuren komen van de website van je zaak. Je kunt alles hieronder aanpassen.")
        }
    }

    /// Logo, kleur en tekstkleur van de website. Lukt het niet: Pasr-kleur en initiaal, zonder fout.
    private func fetchBrand() async {
        brandBusy = true
        defer { brandBusy = false }
        guard let brand = await BusinessAPI.brand(business: business.id, url: business.website) else {
            brandFailed = true
            brandDomain = nil
            if isNew && card.logo == nil { card.color = "#6A5CFF"; card.textColor = nil }
            return
        }
        brandFailed = false
        withAnimation {
            if let logo = brand.logo { card.logo = logo; logoChanged = true }
            if let color = brand.color { card.color = color }
            card.textColor = brand.textColor
            if card.name.trimmingCharacters(in: .whitespaces).isEmpty, let name = brand.name { card.name = String(name.prefix(40)) }
            brandDomain = brand.domain ?? business.website.flatMap { URL(string: $0)?.host() } ?? String(localized: "je website")
        }
    }

    private func save() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            _ = try await BusinessAPI.saveCard(card, business: business, logoChanged: logoChanged)
            saved.toggle()
            await store.load()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func delete() async {
        busy = true
        defer { busy = false }
        do {
            try await BusinessAPI.deleteCard(card.id)
            await store.load()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

/// QR-code, link en flyer (A4-PDF) van een kaart.
struct CardShareView: View {
    let business: Business
    let card: BusinessCard
    @Environment(\.dismiss) private var dismiss
    @State private var flyer: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text("Klanten scannen deze code met hun camera en sparen in Pasr of in de browser.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    if let qr = QRCode.image(card.joinURL.absoluteString) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .accessibilityLabel(Text("QR-code van de kaart"))
                    }
                    Text(verbatim: card.joinURL.absoluteString)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                    ShareLink(item: card.joinURL, subject: Text(verbatim: card.name),
                              message: Text(String(format: String(localized: "Spaar bij %@ met de digitale stempelkaart."), business.name))) {
                        Label("Link delen", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(BigButtonStyle())
                    if let flyer {
                        ShareLink(item: flyer) {
                            Label("Flyer (A4, PDF)", systemImage: "printer")
                        }
                        .buttonStyle(BigButtonStyle(color: Theme.mint, foreground: .black))
                    } else {
                        ProgressView()
                    }
                    Text("Print de flyer en zet hem op de toonbank.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(Text(verbatim: card.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
            .task { flyer = Flyer.makePDF(business: business, card: card) }
        }
    }
}

enum QRCode {
    static func image(_ text: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// A4-flyer voor op de toonbank (zelfde opzet als pasr.nl/zakelijk/flyer).
enum Flyer {
    @MainActor
    static func makePDF(business: Business, card: BusinessCard) -> URL? {
        let safe = card.name.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Flyer \(safe.isEmpty ? "Pasr" : safe).pdf")
        let page = CGSize(width: 595, height: 842)
        let renderer = ImageRenderer(content: FlyerPage(business: business, card: card).frame(width: page.width, height: page.height))
        renderer.proposedSize = ProposedViewSize(page)
        var ok = false
        renderer.render { _, draw in
            var box = CGRect(origin: .zero, size: page)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}

private struct FlyerPage: View {
    let business: Business
    let card: BusinessCard

    var body: some View {
        VStack(spacing: 18) {
            Text("DIGITALE STEMPELKAART")
                .font(.system(size: 13, weight: .heavy)).tracking(2)
                .foregroundStyle(Color(hex: "#6A5CFF"))
            Text(String(format: String(localized: "Spaar bij %@"), business.name))
                .font(.system(size: 36, weight: .heavy))
                .multilineTextAlignment(.center)
            Text(String(format: String(localized: "%lld stempels = %@"), card.stampsTotal, card.reward))
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)
            StampCardView(name: card.name, business: business.name, color: card.color, logo: card.logo,
                          total: card.stampsTotal, filled: (card.stampsTotal + 1) / 2, reward: card.reward, textColor: card.textColor)
                .frame(width: 330)
            if let qr = QRCode.image(card.joinURL.absoluteString, scale: 10) {
                Image(uiImage: qr).interpolation(.none).resizable().frame(width: 210, height: 210)
            }
            Text("Scan met je camera").font(.system(size: 18, weight: .bold))
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Scan de QR-code met de camera van je telefoon.")
                Text("2. Bewaar de kaart in de gratis app Pasr, of gebruik hem in je browser.")
                Text("3. Laat bij elke aankoop je kaart scannen voor een stempel.")
            }
            .font(.system(size: 13))
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image("AppIconDisplay").resizable().frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 5))
                Text(verbatim: "pasr.nl").font(.system(size: 13, weight: .bold))
            }
        }
        .foregroundStyle(Color(hex: "#17162A"))
        .padding(44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
