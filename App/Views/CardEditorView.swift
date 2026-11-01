import SwiftUI
import SwiftData
import PhotosUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Create or edit a card, with a live preview at the top.
struct CardEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let existing: Card?
    private let onSaved: (() -> Void)?

    @State private var draft: Draft
    @State private var showScanner = false
    @State private var codePhoto: PhotosPickerItem?
    @State private var logoItem: PhotosPickerItem?
    @State private var cropRequest: CropRequest?
    @State private var fetchingLogo = false
    @State private var logoMessage: String?
    @State private var frontItem: PhotosPickerItem?
    @State private var backItem: PhotosPickerItem?
    @State private var readingPhoto = false
    @State private var photoMessage: String?
    @State private var confirmDelete = false
    @FocusState private var numberFocused: Bool

    struct Draft {
        var storeName = ""
        var templateID: String?
        var number = ""
        var format: BarcodeFormat = .code128
        var colorHex = "#6A5CFF"
        var kind: CardKind = .loyalty
        var isFavorite = false
        var isLocked = false
        var note = ""
        var balanceText = ""
        var currencyCode = Locale.current.currency?.identifier ?? "EUR"
        var hasExpiry = false
        var expiresAt = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
        var pin = ""
        var logoData: Data?
        var logoFromWebsite = false
        var website = ""
        var frontPhoto: Data?
        var backPhoto: Data?

        var balance: Double? {
            let cleaned = balanceText.replacingOccurrences(of: ",", with: ".")
                .filter { $0.isNumber || $0 == "." }
            return Double(cleaned)
        }

        var appearance: CardAppearance {
            CardAppearance(storeName: storeName, number: number.isEmpty ? "0000000000000" : number, format: format,
                           colorHex: colorHex, kind: kind, isFavorite: isFavorite, logoData: logoData,
                           balance: kind == .voucher ? balance : nil, currencyCode: currencyCode,
                           expiresAt: kind == .voucher && hasExpiry ? expiresAt : nil,
                           logoStyle: logoFromWebsite
                               ? StoreLogoStyles.style(for: StoreTemplates.normalizedDomain(website)
                                   ?? StoreTemplates.template(id: templateID)?.domain)
                               : nil)
        }
    }

    // MARK: Init

    init(card: Card) {
        existing = card
        onSaved = nil
        var d = Draft()
        d.storeName = card.storeName
        d.templateID = card.templateID
        d.number = card.number
        d.format = card.format
        d.colorHex = card.colorHex
        d.kind = card.kind
        d.isFavorite = card.isFavorite
        d.isLocked = card.isLocked
        d.note = card.note
        if let balance = card.balance { d.balanceText = balance.formatted(.number.precision(.fractionLength(2))) }
        d.currencyCode = card.currencyCode ?? d.currencyCode
        d.hasExpiry = card.expiresAt != nil
        d.expiresAt = card.expiresAt ?? d.expiresAt
        d.pin = card.pin ?? ""
        d.logoData = card.logoData
        d.logoFromWebsite = card.logoFromWebsite
        d.website = card.website ?? ""
        d.frontPhoto = card.frontPhoto
        d.backPhoto = card.backPhoto
        _draft = State(initialValue: d)
    }

    init(template: StoreTemplate, onSaved: (() -> Void)? = nil) {
        existing = nil
        self.onSaved = onSaved
        var d = Draft()
        d.storeName = template.name
        d.templateID = template.id
        d.format = template.format
        d.colorHex = template.cardHex
        d.kind = template.kind
        // Known store: its logo is in the app, so the card shows it from the first moment.
        if LogoService.isEnabled, let logo = LogoService.bundledLogo(for: template.domain) {
            d.logoData = logo
            d.logoFromWebsite = true
        }
        _draft = State(initialValue: d)
    }

    init(storeName: String, onSaved: (() -> Void)? = nil) {
        existing = nil
        self.onSaved = onSaved
        var d = Draft()
        d.storeName = storeName
        d.colorHex = Brand.palette.randomElement() ?? "#6A5CFF"
        _draft = State(initialValue: d)
    }

    // MARK: Body

    private var codeIsValid: Bool {
        let value = draft.number.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return false }
        if draft.format.isLinear { return (try? BarcodeEncoder.encode(value, as: draft.format)) != nil }
        return true
    }

    private var canSave: Bool { !draft.storeName.trimmingCharacters(in: .whitespaces).isEmpty && codeIsValid }

    var body: some View {
        Form {
            Section {
                CardFaceView(appearance: draft.appearance)
                    .aspectRatio(Brand.cardAspect, contentMode: .fit)
                    .frame(maxWidth: 380)
                    .frame(maxWidth: .infinity)
                    .animation(.snappy, value: draft.appearance)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

            codeSection
            cardSection
            if draft.kind == .voucher { voucherSection }
            logoSection
            extrasSection

            if existing != nil {
                Section {
                    Button("Verwijder kaart", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Brand.ink.ignoresSafeArea())
        .navigationTitle(existing == nil ? String(localized: "Nieuwe kaart") : String(localized: "Wijzig kaart"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if existing != nil {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Bewaar") { save() }.disabled(!canSave)
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showScanner) {
            ScannerSheet { value, format in
                draft.number = value
                draft.format = format
            }
        }
        .onAppear {
            // New card from a store: open the scanner straight away, like Stocard did.
            if existing == nil && draft.number.isEmpty && ScannerView.isAvailable { showScanner = true }
        }
        #endif
        .task {
            // New card from a store without a logo in the app: fetch it from the website.
            guard existing == nil, draft.logoData == nil, LogoService.isEnabled, let domain = templateDomain else { return }
            if let logo = await LogoService.logo(for: domain), draft.logoData == nil {
                draft.logoData = logo
                draft.logoFromWebsite = true
            }
        }
        .onChange(of: codePhoto) { _, item in Task { await readCode(from: item) } }
        .onChange(of: logoItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                cropRequest = CropRequest(data: data)
                logoItem = nil
            }
        }
        .sheet(item: $cropRequest) { request in
            if let cropper = LogoCropperView(imageData: request.data, onCrop: { png in
                draft.logoData = png
                draft.logoFromWebsite = false
            }) {
                cropper
            } else {
                Text("Deze afbeelding kan niet worden geopend.").padding()
            }
        }
        .onChange(of: frontItem) { _, item in Task { draft.frontPhoto = await loadImage(item, maxSide: 1600) } }
        .onChange(of: backItem) { _, item in Task { draft.backPhoto = await loadImage(item, maxSide: 1600) } }
        .confirmationDialog("Deze kaart naar Recent verwijderd verplaatsen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder", role: .destructive) {
                existing?.deletedAt = .now
                dismiss()
            }
        }
    }

    // MARK: Sections

    private var codeSection: some View {
        Section {
            TextField("Kaartnummer", text: $draft.number)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .focused($numberFocused)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
                .onChange(of: draft.number) { old, new in
                    // Typed by hand: pick EAN-13/EAN-8 automatically when the check digit fits.
                    if numberFocused, draft.templateID == nil, old.isEmpty || draft.format.isLinear {
                        draft.format = BarcodeFormat.guess(for: new)
                    }
                }

            Picker("Soort code", selection: $draft.format) {
                ForEach(BarcodeFormat.allCases) { Text($0.displayName).tag($0) }
            }

            HStack(spacing: 10) {
                #if os(iOS)
                Button { showScanner = true } label: {
                    Label("Scan", systemImage: "barcode.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                #endif
                PhotosPicker(selection: $codePhoto, matching: .images) {
                    Label(readingPhoto ? "Lezen…" : "Uit foto", systemImage: "photo").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            Text("Code")
        } footer: {
            if let photoMessage {
                Text(photoMessage)
            } else if !draft.number.isEmpty && !codeIsValid {
                Text("Dit nummer past niet bij \(draft.format.displayName). Kies een andere soort code.")
                    .foregroundStyle(Brand.coral)
            }
        }
    }

    private var cardSection: some View {
        Section("Kaart") {
            TextField("Winkel", text: $draft.storeName)
            Picker("Soort", selection: $draft.kind) {
                ForEach(CardKind.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Brand.palette, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 30, height: 30)
                            .overlay {
                                Circle().strokeBorder(.white, lineWidth: draft.colorHex.uppercased() == hex ? 2.5 : 0)
                            }
                            .onTapGesture { draft.colorHex = hex }
                            .accessibilityAddTraits(.isButton)
                    }
                    ColorPicker("Eigen kleur", selection: Binding(
                        get: { Color(hex: draft.colorHex) },
                        set: { draft.colorHex = $0.hexString() }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var voucherSection: some View {
        Section("Voucher") {
            HStack {
                Text("Saldo")
                TextField("0,00", text: $draft.balanceText)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Text(draft.currencyCode).foregroundStyle(.secondary)
            }
            TextField("Pincode (optioneel)", text: $draft.pin)
                .font(.system(.body, design: .monospaced))
            Toggle("Vervaldatum", isOn: $draft.hasExpiry.animation())
            if draft.hasExpiry {
                DatePicker("Geldig tot", selection: $draft.expiresAt, displayedComponents: .date)
            }
        }
    }

    private var templateDomain: String? { StoreTemplates.normalizedDomain(StoreTemplates.template(id: draft.templateID)?.domain) }

    private var logoSection: some View {
        Section {
            if let data = draft.logoData, let image = Image(data: data) {
                HStack(spacing: 12) {
                    image.resizable().scaledToFit()
                        .frame(maxWidth: 76, maxHeight: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text(draft.logoFromWebsite ? "Van de website" : "Eigen logo").foregroundStyle(.secondary)
                    Spacer()
                    Button("Verwijder", role: .destructive) {
                        draft.logoData = nil
                        draft.logoFromWebsite = false
                    }
                    .buttonStyle(.borderless)
                }
            }
            PhotosPicker(selection: $logoItem, matching: .images) {
                Label("Uitknippen uit foto of screenshot", systemImage: "scissors")
            }
            if let front = draft.frontPhoto {
                Button { cropRequest = CropRequest(data: front) } label: {
                    Label("Uitknippen uit foto van de voorkant", systemImage: "rectangle.dashed")
                }
            }
            TextField("Website, bijv. \(templateDomain ?? "winkel.nl")", text: $draft.website)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
            Button { Task { await fetchWebsiteLogo() } } label: {
                Label(fetchingLogo ? "Logo ophalen…" : "Logo van de website ophalen", systemImage: "globe")
            }
            .disabled(fetchingLogo || (StoreTemplates.normalizedDomain(draft.website) ?? templateDomain) == nil)
        } header: {
            Text("Logo")
        } footer: {
            Text(logoMessage ?? String(localized: "Pasr haalt het icoon op dat de winkel zelf op zijn website zet. Je kunt ook zelf een logo uitknippen."))
        }
    }

    private var extrasSection: some View {
        Section("Meer") {
            Toggle("Favoriet", isOn: $draft.isFavorite)
            Toggle(isOn: $draft.isLocked) {
                Label("Code afschermen met \(Biometrics.methodName)", systemImage: Biometrics.symbolName)
            }
            TextField("Notitie", text: $draft.note, axis: .vertical).lineLimit(1...4)
            PhotosPicker(selection: $frontItem, matching: .images) {
                Label(draft.frontPhoto == nil ? "Foto van de voorkant" : "Foto voorkant toegevoegd", systemImage: "rectangle.portrait")
            }
            PhotosPicker(selection: $backItem, matching: .images) {
                Label(draft.backPhoto == nil ? "Foto van de achterkant" : "Foto achterkant toegevoegd", systemImage: "rectangle.portrait.fill")
            }
        }
    }

    private func fetchWebsiteLogo() async {
        guard let domain = StoreTemplates.normalizedDomain(draft.website) ?? templateDomain else { return }
        fetchingLogo = true
        defer { fetchingLogo = false }
        if let logo = await LogoService.logo(for: domain, force: true) {
            draft.logoData = logo
            draft.logoFromWebsite = true
            logoMessage = nil
        } else {
            logoMessage = String(localized: "Op \(domain) is geen bruikbaar logo gevonden. Knip er zelf een uit.")
        }
    }

    // MARK: Actions

    private func readCode(from item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        readingPhoto = true
        defer { readingPhoto = false }
        if let result = await ImageCodeReader.read(data) {
            draft.number = result.payload
            draft.format = result.format
            photoMessage = nil
            if draft.storeName.isEmpty, let template = result.template {
                draft.storeName = template.name
                draft.colorHex = template.cardHex
                draft.templateID = template.id
            }
        } else {
            photoMessage = String(localized: "Geen barcode gevonden in deze foto.")
        }
    }

    private func loadImage(_ item: PhotosPickerItem?, maxSide: CGFloat) async -> Data? {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return ImageResizer.jpeg(data, maxSide: maxSide)
    }

    private func save() {
        let card = existing ?? Card()
        card.storeName = draft.storeName.trimmingCharacters(in: .whitespaces)
        card.templateID = draft.templateID
        card.number = draft.number.trimmingCharacters(in: .whitespaces)
        card.format = draft.format
        card.colorHex = draft.colorHex
        card.kind = draft.kind
        card.isFavorite = draft.isFavorite
        card.isLocked = draft.isLocked
        card.note = draft.note
        card.balance = draft.kind == .voucher ? draft.balance : nil
        card.currencyCode = draft.kind == .voucher ? draft.currencyCode : nil
        card.expiresAt = draft.kind == .voucher && draft.hasExpiry ? draft.expiresAt : nil
        card.pin = draft.pin.isEmpty ? nil : draft.pin
        card.logoData = draft.logoData
        card.logoFromWebsite = draft.logoData != nil && draft.logoFromWebsite
        card.website = StoreTemplates.normalizedDomain(draft.website)
        card.frontPhoto = draft.frontPhoto
        card.backPhoto = draft.backPhoto
        card.updatedAt = .now
        card.refreshCodeImage()
        if existing == nil { context.insert(card) }
        try? context.save()
        if card.logoData == nil {
            let context = context
            Task { await LogoService.fillMissing(in: context) }
        }
        if let onSaved { onSaved() } else { dismiss() }
    }
}

enum ImageResizer {
    static func jpeg(_ data: Data, maxSide: CGFloat, quality: CGFloat = 0.82) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
        #else
        guard let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(cg.width, cg.height)))
        let width = Int(CGFloat(cg.width) * scale), height = Int(CGFloat(cg.height) * scale)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .jpeg, properties: [.compressionFactor: quality])
        #endif
    }
}
