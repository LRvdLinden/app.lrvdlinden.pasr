import SwiftUI
import SwiftData
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

// MARK: Cadeaubon-gids

/// "Zo besteed je hem": de gids uit het beheer (geldigheid, online of in de winkel, uitleg, verzendkosten, voorwaarden).
struct GiftGuideRows: View {
    let guide: StoreGuide

    var body: some View {
        if let validity = guide.validity {
            row("calendar.badge.clock", Brand.iris, String(localized: "Geldigheid"), validity)
        }
        if guide.online != nil || guide.store != nil {
            row(guide.online == true && guide.store == true ? "bag.fill" : guide.online == true ? "globe" : "storefront.fill",
                Brand.mint, String(localized: "Inwisselen"), whereText)
        }
        if let how = guide.how {
            row("text.bubble.fill", .orange, String(localized: "Zo werkt het"), how)
        }
        if let shipping = guide.shipping {
            row("shippingbox.fill", Brand.coral, String(localized: "Verzendkosten"), shipping)
        }
        if let terms = guide.terms {
            Link(destination: terms) {
                HStack(spacing: 12) {
                    icon("doc.text.fill", .gray)
                    Text("Voorwaarden van de uitgever").foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var whereText: String {
        switch (guide.online, guide.store) {
        case (true, true): String(localized: "Online en in de winkel")
        case (true, false): String(localized: "Alleen online")
        case (false, true): String(localized: "Alleen in de winkel")
        case (true, nil): String(localized: "Online")
        case (nil, true): String(localized: "In de winkel")
        case (false, false): String(localized: "Niet online en niet in de winkel")
        case (false, nil): String(localized: "Niet online")
        case (nil, false): String(localized: "Niet in de winkel")
        default: ""
        }
    }

    private func icon(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func row(_ symbol: String, _ color: Color, _ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon(symbol, color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote).foregroundStyle(.secondary)
                Text(value)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Haal meer uit je kaart": de programmagids van een klantenkaart (sparen, voordelen, officiële pagina).
struct ProgramGuideSection: View {
    let guide: StoreGuide?

    var body: some View {
        if let guide, guide.hasProgramInfo {
            Section {
                if let earn = guide.earn {
                    HStack(alignment: .top, spacing: 12) {
                        guideIcon("star.circle.fill", .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zo spaar je").font(.footnote).foregroundStyle(.secondary)
                            Text(earn)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(guide.perks ?? [], id: \.self) { perk in
                    HStack(alignment: .top, spacing: 12) {
                        guideIcon("checkmark.seal.fill", Brand.mint)
                        Text(perk)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Voordeel: \(perk)"))
                }
                if let program = guide.program {
                    Link(destination: program) {
                        HStack(spacing: 12) {
                            guideIcon("arrow.up.forward.app.fill", Brand.iris)
                            Text("Officiële programmapagina").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text("Haal meer uit je kaart")
            } footer: {
                if let checked = guide.checkedText {
                    Text("Uit de officiële informatie van de winkel, gecontroleerd op \(checked). Voorwaarden kunnen veranderen.")
                }
            }
        }
    }
}

func guideIcon(_ symbol: String, _ color: Color) -> some View {
    Image(systemName: symbol)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
}

/// De gids als sectie in een formulier of lijst, met (als die er is) de saldo-checker.
struct GiftGuideSection: View {
    let guide: StoreGuide?
    var balancePage: URL? = nil
    var onCheckBalance: ((URL) -> Void)? = nil

    var body: some View {
        if guide?.hasGiftInfo == true || (balancePage != nil && onCheckBalance != nil) {
            Section {
                if let guide, guide.hasGiftInfo { GiftGuideRows(guide: guide) }
                if let balancePage, let onCheckBalance {
                    Button { onCheckBalance(balancePage) } label: {
                        Label("Saldo checken bij \(balancePage.host() ?? String(localized: "de uitgever"))", systemImage: "safari")
                    }
                }
            } header: {
                Text("Zo besteed je hem")
            } footer: {
                if let checked = guide?.checkedText {
                    Text("Uit de officiële voorwaarden, gecontroleerd op \(checked). Check bij twijfel de site van de uitgever.")
                }
            }
        }
    }
}

// MARK: Pasdetails

/// Alles over een pas, zoals de achterkant van een pas in Apple Wallet: gegevens per soort, de cadeaubon-gids,
/// foto's, de notitie en verwijderen.
struct CardInfoSheet: View {
    @Bindable var card: Card
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var checking: URL?
    @State private var adjust = false
    @State private var viewing: PhotoItem?
    @State private var copied = false

    struct PhotoItem: Identifiable {
        let id = UUID()
        let data: Data
        let title: String
    }

    private var details: CardDetails { card.details }

    private var photos: [PhotoItem] {
        var list: [PhotoItem] = []
        if let f = card.frontPhoto { list.append(PhotoItem(data: f, title: String(localized: "Voorkant"))) }
        if let b = card.backPhoto { list.append(PhotoItem(data: b, title: String(localized: "Achterkant"))) }
        let captions = details.captions ?? []
        for (i, data) in card.notePhotos.enumerated() {
            let caption = i < captions.count ? captions[i] : ""
            list.append(PhotoItem(data: data, title: caption.isEmpty ? String(localized: "Foto \(i + 1)") : caption))
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: card.kind.symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color(hex: card.colorHex), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.storeName).font(.headline)
                            Text(card.kind.displayName).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    kindRows
                }

                if card.kind == .loyalty {
                    ProgramGuideSection(guide: RemoteStores.guide(for: card.templateID, storeName: card.storeName))
                }
                if card.kind == .voucher {
                    GiftGuideSection(guide: RemoteStores.guide(for: card.templateID, storeName: card.storeName),
                                     balancePage: card.isTemporary ? nil : card.balancePage,
                                     onCheckBalance: { url in
                                         CardClipboard.copy(card.number)
                                         checking = url
                                     })
                }

                if !photos.isEmpty {
                    Section("Foto's") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                            ForEach(photos) { item in
                                Button { viewing = item } label: {
                                    VStack(spacing: 4) {
                                        if let image = Image(data: item.data) {
                                            image.resizable().scaledToFill()
                                                .frame(height: 84)
                                                .frame(maxWidth: .infinity)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                        Text(item.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(item.title))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !card.note.isEmpty {
                    Section("Notitie") { Text(card.note).textSelection(.enabled) }
                }

                Section {
                    Button(role: .destructive) {
                        dismiss()
                        onDelete()
                    } label: {
                        Label("Verwijder kaart", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar", systemImage: "checkmark") { dismiss() } } }
            .sheet(item: $viewing) { item in PhotoViewer(data: item.data, title: item.title) }
            .sheet(isPresented: $adjust) {
                SpendSheet(card: card, mode: .set).presentationDetents([.medium])
            }
            #if canImport(SafariServices)
            .sheet(item: Binding(get: { checking.map(IdentifiedURL.init) }, set: { checking = $0?.url })) { item in
                SafariView(url: item.url).ignoresSafeArea()
                    .onDisappear {
                        Task { try? await Task.sleep(for: .milliseconds(450)); adjust = true }
                    }
            }
            #endif
        }
    }

    @ViewBuilder private var kindRows: some View {
        switch card.kind {
        case .loyalty:
            if !card.number.isEmpty { LabeledContent("Nummer", value: CardAppearance(card).groupedNumber) }
        case .voucher:
            if let balance = CardAppearance(card).balanceText { LabeledContent("Tegoed", value: balance) }
            if let expires = card.expiresAt { LabeledContent("Geldig tot", value: expires.formatted(date: .long, time: .omitted)) }
            if let pin = card.pin, !pin.isEmpty, !card.isLocked { LabeledContent("Pincode", value: pin) }
        case .code:
            if !card.number.isEmpty {
                Button {
                    CardClipboard.copy(card.number)
                    withAnimation { copied = true }
                } label: {
                    LabeledContent {
                        Label(copied ? "Gekopieerd" : "Kopieer", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                    } label: {
                        Text(card.number).font(.system(.body, design: .monospaced).weight(.semibold))
                    }
                }
                .tint(.primary)
            }
            if let expires = card.expiresAt { LabeledContent("Geldig tot", value: expires.formatted(date: .long, time: .omitted)) }
            if let shop = card.website, let url = URL(string: "https://" + shop) {
                Link(destination: url) { Label("Naar \(shop)", systemImage: "cart") }
            }
        case .ticket:
            if let date = details.eventDate { LabeledContent("Datum", value: date.formatted(date: .long, time: .shortened)) }
            if let venue = details.venue, !venue.isEmpty {
                LabeledContent("Locatie", value: venue)
                if let url = URL(string: "maps://?q=" + (venue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                    Link(destination: url) { Label("Open in Kaarten", systemImage: "map") }
                }
            }
            if let seat = details.seat, !seat.isEmpty { LabeledContent("Plaats", value: seat) }
        case .subscription:
            if let cost = details.cost {
                LabeledContent("Kosten", value: cost.formatted(.currency(code: card.currencyCode ?? "EUR")) + " " + details.periodValue.title)
            }
            if let renews = details.renewsAt { LabeledContent("Verlengt op", value: renews.formatted(date: .long, time: .omitted)) }
            if !card.number.isEmpty { LabeledContent("Lidnummer", value: card.number) }
        }
    }
}

/// Een foto groot bekijken, met in- en uitzoomen.
struct PhotoViewer: View {
    let data: Data
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = Image(data: data) {
                    image.resizable().scaledToFit()
                        .scaleEffect(scale * pinch)
                        .gesture(MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in scale = min(max(1, scale * value.magnification), 5) })
                        .onTapGesture(count: 2) { withAnimation(.snappy) { scale = scale > 1 ? 1 : 2.5 } }
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar", systemImage: "checkmark") { dismiss() } } }
        }
    }
}

// MARK: Eigen voorkant

/// Een foto als voorkant van de kaart: schuif en zoom de foto achter een kader op kaartformaat.
struct CoverCropperView: View {
    let image: CGImage
    var onCrop: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Zoom (1 = de foto vult het kader precies) en verschuiving in punten.
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1

    init?(imageData: Data, onCrop: @escaping (Data) -> Void) {
        guard let image = ImageTools.cgImage(from: imageData, maxSide: 3000) else { return nil }
        self.image = image
        self.onCrop = onCrop
    }

    private var imageAspect: CGFloat { CGFloat(image.width) / CGFloat(image.height) }

    /// Grootte van de foto (in punten) bij zoom 1: precies zo groot dat hij het kader vult.
    private func baseSize(frame: CGSize) -> CGSize {
        if imageAspect > frame.width / frame.height {
            return CGSize(width: frame.height * imageAspect, height: frame.height)
        }
        return CGSize(width: frame.width, height: frame.width / imageAspect)
    }

    /// Verschuiving begrensd, zodat het kader altijd gevuld blijft.
    private func clamped(_ o: CGSize, zoom z: CGFloat, frame: CGSize) -> CGSize {
        let size = baseSize(frame: frame)
        let maxX = max(0, (size.width * z - frame.width) / 2), maxY = max(0, (size.height * z - frame.height) / 2)
        return CGSize(width: min(max(o.width, -maxX), maxX), height: min(max(o.height, -maxY), maxY))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Schuif de foto in het kader en knijp om in te zoomen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                GeometryReader { geo in
                    let width = min(geo.size.width - 32, 460)
                    let frame = CGSize(width: width, height: width / Brand.cardAspect)
                    let z = min(max(1, zoom * pinch), 6)
                    let size = baseSize(frame: frame)
                    let o = clamped(CGSize(width: offset.width + drag.width, height: offset.height + drag.height), zoom: z, frame: frame)
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: size.width * z, height: size.height * z)
                        .offset(o)
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 2))
                        .contentShape(Rectangle())
                        .gesture(DragGesture()
                            .updating($drag) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                offset = clamped(CGSize(width: offset.width + value.translation.width,
                                                        height: offset.height + value.translation.height), zoom: zoom, frame: frame)
                            })
                        .simultaneousGesture(MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in
                                zoom = min(max(1, zoom * value.magnification), 6)
                                offset = clamped(offset, zoom: zoom, frame: frame)
                            })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Gebruik", systemImage: "checkmark") {
                                    if let data = render(frame: frame) { onCrop(data) }
                                    dismiss()
                                }
                            }
                        }
                }
                HStack(spacing: 12) {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { zoom }, set: { zoom = $0 }), in: 1...6)
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Eigen voorkant")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer", systemImage: "xmark") { dismiss() } }
            }
        }
    }

    /// Het stuk binnen het kader als JPEG (1000 pixels breed).
    private func render(frame: CGSize) -> Data? {
        let size = baseSize(frame: frame)
        let o = clamped(offset, zoom: zoom, frame: frame)
        let shown = CGSize(width: size.width * zoom, height: size.height * zoom)
        // linksboven van het kader, gemeten in de getoonde foto
        let x = (shown.width - frame.width) / 2 - o.width
        let y = (shown.height - frame.height) / 2 - o.height
        let rect = CGRect(x: x / shown.width, y: y / shown.height,
                          width: frame.width / shown.width, height: frame.height / shown.height)
        guard let cropped = ImageTools.crop(image, to: rect) else { return nil }
        return ImageTools.jpeg(cropped, width: 1000, aspect: Brand.cardAspect)
    }
}

extension ImageTools {
    /// JPEG op een vaste breedte en verhouding (voor de eigen voorkant).
    static func jpeg(_ image: CGImage, width: Int, aspect: CGFloat, quality: CGFloat = 0.72) -> Data? {
        let w = min(width, max(1, image.width)), h = max(1, Int(CGFloat(w) / aspect))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
