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
    @State private var pickingPlace = false
    @State private var noteItems: [PhotosPickerItem] = []
    @State private var coverItem: PhotosPickerItem?
    @State private var coverRequest: CropRequest?
    @State private var viewingPhoto: CardInfoSheet.PhotoItem?
    @State private var checkingBalance: URL?
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
        /// Privé (nil) of een gedeelde Pasr.
        var groupID: UUID?
        /// Eigen locaties (Ik sta hier / speld op de kaart).
        var places: [CardPlace] = []
        /// Eigen saldo-pagina (voucher).
        var balanceURL = ""
        /// Ticket, abonnement, kortingscode.
        var details = CardDetails()
        var hasRenewal = false
        var renewsAt = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
        var eventDate = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: .now.addingTimeInterval(7 * 86_400)) ?? .now
        var costText = ""
        /// Foto-notities (bonnetje, voorwaarden) met onderschrift, en de eigen voorkant.
        var notePhotos: [Data] = []
        var captions: [String] = []
        var cover: Data?

        var cost: Double? {
            Double(costText.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." })
        }

        /// Kortingscode als tekst (standaard) of als barcode.
        var codeAsText: Bool { kind == .code && details.codeAsBarcode != true }

        /// De gegevens zoals ze bewaard worden (alleen wat bij de soort hoort).
        var savedDetails: CardDetails {
            var d = CardDetails()
            switch kind {
            case .ticket:
                d.eventDate = eventDate
                d.venue = details.venue?.trimmingCharacters(in: .whitespaces).nilIfEmpty
                d.seat = details.seat?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            case .subscription:
                d.renewsAt = hasRenewal ? renewsAt : nil
                d.cost = cost
                d.period = details.periodValue.rawValue
            case .code:
                d.codeAsBarcode = details.codeAsBarcode == true ? true : nil
            default: break
            }
            let caps = Array(captions.prefix(notePhotos.count)).map { $0.trimmingCharacters(in: .whitespaces) }
            d.captions = caps.allSatisfy(\.isEmpty) ? nil : caps
            return d
        }

        var balance: Double? {
            let cleaned = balanceText.replacingOccurrences(of: ",", with: ".")
                .filter { $0.isNumber || $0 == "." }
            return Double(cleaned)
        }

        var appearance: CardAppearance {
            var a = CardAppearance(storeName: storeName,
                           number: number.isEmpty ? (kind == .subscription ? "" : kind == .code ? "CODE" : "0000000000000") : number,
                           format: format,
                           colorHex: colorHex, kind: kind, isFavorite: isFavorite, logoData: logoData,
                           balance: kind == .voucher ? balance : nil, currencyCode: currencyCode,
                           expiresAt: kind.hasExpiry && hasExpiry ? expiresAt : nil,
                           logoStyle: logoFromWebsite
                               ? StoreLogoStyles.style(for: StoreTemplates.normalizedDomain(website)
                                   ?? StoreTemplates.template(id: templateID)?.domain)
                               : nil)
            a.details = savedDetails
            a.codeAsText = codeAsText
            a.cover = cover
            return a
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
        d.groupID = card.groupID
        d.places = card.places
        d.balanceURL = card.balanceURL ?? ""
        let details = card.details
        d.details = details
        if let date = details.eventDate { d.eventDate = date }
        d.hasRenewal = details.renewsAt != nil
        if let date = details.renewsAt { d.renewsAt = date }
        if let cost = details.cost { d.costText = cost.formatted(.number.precision(.fractionLength(2))) }
        d.notePhotos = card.notePhotos
        d.captions = details.captions ?? []
        d.cover = card.coverPhoto
        _draft = State(initialValue: d)
    }

    init(template: StoreTemplate, number: String? = nil, format: BarcodeFormat? = nil, onSaved: (() -> Void)? = nil) {
        existing = nil
        self.onSaved = onSaved
        var d = Draft()
        d.storeName = template.name
        d.templateID = template.id
        d.format = format ?? template.format
        d.number = number ?? ""
        d.colorHex = template.cardHex
        d.kind = template.kind
        // Known store: its logo is in the app, so the card shows it from the first moment.
        if LogoService.isEnabled, let logo = LogoService.bundledLogo(for: template.domain) {
            d.logoData = logo
            d.logoFromWebsite = true
        }
        _draft = State(initialValue: d)
    }

    init(storeName: String, kind: CardKind = .loyalty, number: String? = nil, format: BarcodeFormat? = nil,
         onSaved: (() -> Void)? = nil) {
        existing = nil
        self.onSaved = onSaved
        var d = Draft()
        d.storeName = storeName
        d.kind = kind
        d.number = number ?? ""
        if let format { d.format = format } else if kind == .ticket { d.format = .qr }
        d.colorHex = Brand.palette.randomElement() ?? "#6A5CFF"
        _draft = State(initialValue: d)
    }

    // MARK: Body

    private var codeIsValid: Bool {
        let value = draft.number.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return draft.kind == .subscription }   // een abonnement mag zonder lidnummer
        if draft.codeAsText { return true }
        if draft.format.isLinear { return (try? BarcodeEncoder.encode(value, as: draft.format)) != nil }
        return true
    }

    private var placesStoreName: String { StoreTemplates.template(id: draft.templateID)?.name ?? draft.storeName }

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
                .disabled(existing?.isTemporary == true)
            if showsPlacePicker { placeSection }
            cardSection
            switch draft.kind {
            case .voucher:
                voucherSection
                GiftGuideSection(guide: RemoteStores.guide(for: draft.templateID, storeName: draft.storeName),
                                 balancePage: balancePageURL,
                                 onCheckBalance: { url in
                                     CardClipboard.copy(draft.number)
                                     checkingBalance = url
                                 })
            case .code: discountSection
            case .ticket: ticketSection
            case .subscription: subscriptionSection
            case .loyalty: EmptyView()
            }
            logoSection
            photosSection
            extrasSection
            if existing?.isTemporary != true {
                CardPlacesSection(places: $draft.places, storeName: placesStoreName) { pickingPlace = true }
            }

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
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer", systemImage: "xmark") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Bewaar", systemImage: "checkmark") { save() }.disabled(!canSave)
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
            // New card from a store: open the scanner straight away, like the old card apps did.
            if existing == nil && draft.number.isEmpty && ScannerView.isAvailable,
               draft.kind != .code && draft.kind != .subscription { showScanner = true }
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
        .sheet(isPresented: $pickingPlace) {
            PlacePickerView(storeName: placesStoreName, existing: draft.places) { picked in
                draft.places = Array((draft.places + picked).prefix(CardPlace.maxPerCard))
                pickingPlace = false
            }
        }
        .onChange(of: frontItem) { _, item in Task { draft.frontPhoto = await loadImage(item, maxSide: 1600) } }
        .onChange(of: noteItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items where draft.notePhotos.count < Card.maxNotePhotos {
                    if let data = await loadImage(item, maxSide: 1600) {
                        draft.notePhotos.append(data)
                        if draft.captions.count < draft.notePhotos.count { draft.captions.append("") }
                    }
                }
                noteItems = []
            }
        }
        .onChange(of: coverItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                coverRequest = CropRequest(data: data)
                coverItem = nil
            }
        }
        .sheet(item: $coverRequest) { request in
            if let cropper = CoverCropperView(imageData: request.data, onCrop: { draft.cover = $0 }) {
                cropper
            } else {
                Text("Deze afbeelding kan niet worden geopend.").padding()
            }
        }
        .sheet(item: $viewingPhoto) { item in PhotoViewer(data: item.data, title: item.title) }
        #if canImport(SafariServices)
        .sheet(item: Binding(get: { checkingBalance.map(IdentifiedURL.init) }, set: { checkingBalance = $0?.url })) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
        #endif
        .onChange(of: backItem) { _, item in Task { draft.backPhoto = await loadImage(item, maxSide: 1600) } }
        .confirmationDialog("Deze kaart verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder", role: .destructive) {
                existing?.deletedAt = .now
                dismiss()
            }
        }
    }

    // MARK: Sections

    private var codeSection: some View {
        Section {
            TextField(draft.kind == .subscription ? String(localized: "Lidnummer (optioneel)") : draft.kind.codeLabel,
                      text: $draft.number)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .focused($numberFocused)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
                .onChange(of: draft.number) { old, new in
                    // Typed by hand: pick EAN-13/EAN-8 automatically when the check digit fits.
                    if numberFocused, draft.templateID == nil, !draft.codeAsText, draft.kind != .ticket,
                       old.isEmpty || draft.format.isLinear {
                        draft.format = BarcodeFormat.guess(for: new)
                    }
                }

            if draft.kind == .code {
                Toggle(isOn: Binding(get: { draft.details.codeAsBarcode == true },
                                     set: { draft.details.codeAsBarcode = $0 ? true : nil }).animation()) {
                    Label("Toon als barcode of QR", systemImage: "barcode")
                }
            }
            if !draft.codeAsText {
                Picker("Soort code", selection: $draft.format) {
                    ForEach(BarcodeFormat.allCases) { Text($0.displayName).tag($0) }
                }
            }

            HStack(spacing: 10) {
                #if os(iOS)
                if ScannerView.isAvailable {   // niet op de Mac of Vision Pro
                    Button { showScanner = true } label: {
                        Label("Scan", systemImage: "barcode.viewfinder").frame(maxWidth: .infinity)
                    }
                    .pasrGlassButton()
                }
                #endif
                PhotosPicker(selection: $codePhoto, matching: .images) {
                    Label(readingPhoto ? "Lezen…" : "Uit foto", systemImage: "photo").frame(maxWidth: .infinity)
                }
                .pasrGlassButton()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            Text("Code")
        } footer: {
            if let photoMessage {
                Text(photoMessage)
            } else if draft.codeAsText {
                Text("Typ of plak de code. Zet Toon als barcode aan als de winkel hem wil scannen.")
            } else if !draft.number.isEmpty && !codeIsValid {
                Text("Dit nummer past niet bij \(draft.format.displayName). Kies een andere soort code.")
                    .foregroundStyle(Brand.coral)
            }
        }
    }

    private var cardSection: some View {
        Section("Kaart") {
            TextField("Winkel", text: $draft.storeName)
            Picker(selection: $draft.kind.animation()) {
                ForEach(CardKind.allCases) { Label($0.displayName, systemImage: $0.symbol).tag($0) }
            } label: {
                Label("Soort", systemImage: draft.kind.symbol)
            }
            .pickerStyle(.menu)

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

    // MARK: Bewaren in (privé of een gedeelde Pasr)

    private var showsPlacePicker: Bool {
        guard AccountService.shared.isSignedIn, existing?.isTemporary != true else { return false }
        return !GroupService.shared.groups.isEmpty || draft.groupID != nil
    }

    private var placeSection: some View {
        Section {
            Picker(selection: $draft.groupID) {
                Label("Privé", systemImage: "person.fill").tag(UUID?.none)
                ForEach(GroupService.shared.groups) { group in
                    Label(group.name, systemImage: "person.2.fill").tag(UUID?.some(group.id))
                }
                if let id = draft.groupID, GroupService.shared.group(id) == nil {
                    Label("Gedeelde Pasr", systemImage: "person.2.fill").tag(UUID?.some(id))
                }
            } label: {
                Label("Bewaren in", systemImage: "tray.full")
            }
        } footer: {
            if let id = draft.groupID {
                Text("Iedereen in \(GroupService.shared.group(id)?.name ?? String(localized: "deze gedeelde Pasr")) ziet en gebruikt deze kaart.")
            } else if existing?.groupID != nil {
                Text("De kaart gaat uit de gedeelde Pasr en wordt alleen van jou.")
            } else {
                Text("Alleen jij ziet deze kaart.")
            }
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
            TextField(BalancePages.url(for: draft.templateID).map { String(localized: "Saldo-pagina (\(URL(string: $0)?.host() ?? $0))") }
                      ?? String(localized: "Saldo-pagina (website, optioneel)"), text: $draft.balanceURL)
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
        }
    }

    private var balancePageURL: URL? {
        let raw = draft.balanceURL.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? BalancePages.url(for: draft.templateID)
        guard let raw, let url = URL(string: raw.hasPrefix("http") ? raw : "https://" + raw), url.scheme == "https" else { return nil }
        return url
    }

    private var discountSection: some View {
        Section("Kortingscode") {
            TextField("Webshop, bijv. \(templateDomain ?? "winkel.nl")", text: $draft.website)
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
            Toggle("Vervaldatum", isOn: $draft.hasExpiry.animation())
            if draft.hasExpiry {
                DatePicker("Geldig tot", selection: $draft.expiresAt, displayedComponents: .date)
            }
        }
    }

    private var ticketSection: some View {
        Section("Ticket") {
            DatePicker("Datum en tijd", selection: $draft.eventDate)
            TextField("Locatie, bijv. Ziggo Dome", text: Binding(get: { draft.details.venue ?? "" },
                                                                  set: { draft.details.venue = $0 }))
            TextField("Plaats (rij, stoel, vak)", text: Binding(get: { draft.details.seat ?? "" },
                                                                set: { draft.details.seat = $0 }))
        }
    }

    private var subscriptionSection: some View {
        Section {
            HStack {
                Text("Kosten")
                TextField("0,00", text: $draft.costText)
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Text(draft.currencyCode).foregroundStyle(.secondary)
            }
            Picker("Per", selection: Binding(get: { draft.details.periodValue }, set: { draft.details.period = $0.rawValue })) {
                ForEach(CardDetails.Period.allCases) { Text($0.name).tag($0) }
            }
            Toggle("Verlengdatum", isOn: $draft.hasRenewal.animation())
            if draft.hasRenewal {
                DatePicker("Verlengt op", selection: $draft.renewsAt, displayedComponents: .date)
            }
        } header: {
            Text("Abonnement")
        } footer: {
            Text("Met een verlengdatum krijg je twee dagen ervoor een herinnering, zodat je op tijd kunt opzeggen.")
        }
    }

    /// Eigen voorkant en tot vier foto-notities (bonnetje, voorwaarden).
    private var photosSection: some View {
        Section {
            if let cover = draft.cover, let image = Image(data: cover) {
                HStack(spacing: 12) {
                    image.resizable().scaledToFill()
                        .frame(width: 76, height: 76 / Brand.cardAspect)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text("Eigen voorkant").foregroundStyle(.secondary)
                    Spacer()
                    Button("Verwijder", role: .destructive) { draft.cover = nil }
                        .buttonStyle(.borderless)
                }
            }
            PhotosPicker(selection: $coverItem, matching: .images) {
                Label(draft.cover == nil ? "Foto als voorkant" : "Andere foto als voorkant", systemImage: "photo.artframe")
            }
            if let front = draft.frontPhoto {
                Button { coverRequest = CropRequest(data: front) } label: {
                    Label("Foto van de voorkant gebruiken", systemImage: "crop")
                }
            }

            ForEach(Array(draft.notePhotos.enumerated()), id: \.offset) { index, data in
                HStack(spacing: 12) {
                    Button {
                        viewingPhoto = CardInfoSheet.PhotoItem(data: data, title: caption(index).nilIfEmpty ?? String(localized: "Foto \(index + 1)"))
                    } label: {
                        if let image = Image(data: data) {
                            image.resizable().scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .buttonStyle(.borderless)
                    TextField("Onderschrift, bijv. Bonnetje", text: Binding(get: { caption(index) }, set: { setCaption($0, at: index) }))
                    Button(role: .destructive) { removePhoto(at: index) } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Verwijder foto"))
                }
            }
            if draft.notePhotos.count < Card.maxNotePhotos {
                PhotosPicker(selection: $noteItems, maxSelectionCount: Card.maxNotePhotos - draft.notePhotos.count, matching: .images) {
                    Label("Foto toevoegen", systemImage: "photo.badge.plus")
                }
            }
        } header: {
            Text("Foto's")
        } footer: {
            Text("Tot \(Card.maxNotePhotos) foto's per pas, zoals een bonnetje of de voorwaarden. Foto's blijven op je apparaten (iCloud); een kleine eigen voorkant gaat ook mee in je Pasr-account.")
        }
    }

    private func caption(_ index: Int) -> String { index < draft.captions.count ? draft.captions[index] : "" }

    private func setCaption(_ text: String, at index: Int) {
        while draft.captions.count <= index { draft.captions.append("") }
        draft.captions[index] = String(text.prefix(40))
    }

    private func removePhoto(at index: Int) {
        guard index < draft.notePhotos.count else { return }
        draft.notePhotos.remove(at: index)
        if index < draft.captions.count { draft.captions.remove(at: index) }
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
            if draft.kind != .code {   // bij een kortingscode staat de webshop al hierboven
                TextField("Website, bijv. \(templateDomain ?? "winkel.nl")", text: $draft.website)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
            }
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
        // een soort die deze versie niet kent (van een nieuwere Pasr) blijft staan zolang je hem niet wijzigt
        if CardKind(rawValue: card.kindRaw) != nil || draft.kind != .loyalty || existing == nil { card.kind = draft.kind }
        card.isFavorite = draft.isFavorite
        card.isLocked = draft.isLocked
        card.note = draft.note
        let newBalance = draft.kind == .voucher ? draft.balance : nil
        let balanceChanged = existing != nil && newBalance != nil && newBalance != card.balance
        card.balance = newBalance
        card.currencyCode = draft.kind == .voucher ? draft.currencyCode : nil
        card.expiresAt = draft.kind.hasExpiry && draft.hasExpiry ? draft.expiresAt : nil
        if draft.kind == .subscription { card.currencyCode = draft.currencyCode }
        card.details = draft.savedDetails
        card.setNotePhotos(draft.notePhotos)
        card.coverPhoto = draft.cover
        card.pin = draft.pin.isEmpty ? nil : draft.pin
        card.logoData = draft.logoData
        card.logoFromWebsite = draft.logoData != nil && draft.logoFromWebsite
        card.website = StoreTemplates.normalizedDomain(draft.website)
        card.frontPhoto = draft.frontPhoto
        card.backPhoto = draft.backPhoto
        if !card.isTemporary { card.places = draft.places }
        let url = draft.balanceURL.trimmingCharacters(in: .whitespaces)
        card.balanceURL = url.isEmpty ? nil : url
        if balanceChanged, let b = newBalance { card.recordBalance(b) }
        card.updatedAt = .now
        card.refreshCodeImage()
        if existing == nil {
            card.groupID = draft.groupID
            context.insert(card)
            try? context.save()
        } else if card.groupID != draft.groupID, !card.isTemporary {
            // naar een andere plek: kopie op de nieuwe plek, het origineel gaat weg op de oude
            GroupService.move(card, to: draft.groupID, in: context)
        } else {
            try? context.save()
        }
        if card.logoData == nil {
            let context = context
            Task { await LogoService.fillMissing(in: context) }
        }
        let saved = card
        Task { await WalletPass.refreshIfInWallet(saved) }
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
