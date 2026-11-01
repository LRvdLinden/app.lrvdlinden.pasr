import SwiftUI
import SwiftData
import VisionKit
import Vision

/// "Scan je kaart": point the camera at the physical card. Pasr reads the barcode and, from the text and logo
/// on the card, recognises the store, and adds the card straight away. Unknown store: you pick it yourself,
/// with the number already filled in.
struct CardScanView: View {
    /// The card was added.
    var onAdded: (Card) -> Void
    /// The barcode was read but the store wasn't recognised.
    var onUnknownStore: (String, BarcodeFormat) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @State private var added: Card?
    @State private var duplicate: Card?
    @State private var scanID = UUID()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let added {
                result(added, title: "Toegevoegd", subtitle: "\(added.storeName) staat nu in Pasr.", symbol: "checkmark.circle.fill", tint: Brand.mint)
            } else if let duplicate {
                result(duplicate, title: "Staat er al in", subtitle: "Deze kaart van \(duplicate.storeName) heb je al in Pasr.", symbol: "info.circle.fill", tint: Brand.iris)
            } else if CardScanner.isAvailable {
                CardScanner(onResult: handle)
                    .id(scanID)
                    .ignoresSafeArea()
                    .overlay { viewfinder }
            } else {
                ContentUnavailableView("Camera niet beschikbaar", systemImage: "camera.metering.unknown",
                                       description: Text("Geef Pasr toegang tot de camera in Instellingen."))
                    .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
            }
            .pasrGlassButton()
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }

    private var viewfinder: some View {
        VStack(spacing: 0) {
            Spacer()
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, dash: [26, 14]))
                .aspectRatio(Brand.cardAspect, contentMode: .fit)
                .padding(.horizontal, 28)
                .allowsHitTesting(false)
            Spacer()
            VStack(spacing: 6) {
                Text("Leg je kaart in het kader").font(.headline)
                Text("Met de barcode en de naam of het logo in beeld. Pasr herkent de winkel en zet de kaart er meteen in.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .pasrGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
    }

    private func result(_ card: Card, title: LocalizedStringKey, subtitle: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 22) {
            Spacer()
            CardFaceView(appearance: CardAppearance(card), showsCode: false)
                .aspectRatio(Brand.cardAspect, contentMode: .fit)
                .padding(.horizontal, 32)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            Label(title, systemImage: symbol)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
            Text(subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    onAdded(card)
                    dismiss()
                } label: {
                    Text("Klaar").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent).tint(Brand.iris)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button("Nog een kaart scannen") {
                    withAnimation { added = nil; duplicate = nil; scanID = UUID() }
                }
                .font(.callout.weight(.medium))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
    }

    private func handle(_ scan: CardScanner.Scan) {
        let compact = scan.payload.replacingOccurrences(of: " ", with: "")
        if let existing = cards.first(where: { $0.number.replacingOccurrences(of: " ", with: "") == compact }) {
            withAnimation(.snappy) { duplicate = existing }
            return
        }
        guard let template = scan.template else {
            onUnknownStore(scan.payload, scan.format)
            dismiss()
            return
        }
        let card = Card(storeName: template.name, number: scan.payload, format: scan.format,
                        kind: template.kind, colorHex: template.cardHex)
        card.templateID = template.id
        if LogoService.isEnabled, let logo = LogoService.bundledLogo(for: template.domain) {
            card.logoData = logo
            card.logoFromWebsite = true
        }
        card.refreshCodeImage()
        context.insert(card)
        try? context.save()
        if card.logoData == nil { Task { await LogoService.fillMissing(in: context) } }
        withAnimation(.snappy) { added = card }
    }
}

/// Camera that reads the barcode and the text on a card at the same time. After the first barcode it keeps
/// looking for about a second to read the store name, and also reads a still photo, then reports once.
struct CardScanner: UIViewControllerRepresentable {
    struct Scan {
        var payload: String
        var format: BarcodeFormat
        var template: StoreTemplate?
    }

    var onResult: (Scan) -> Void

    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(), .text(languages: ["nl-NL", "en-US"])],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: false
        )
        controller.delegate = context.coordinator
        context.coordinator.scanner = controller
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning { try? controller.startScanning() }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onResult: (Scan) -> Void
        weak var scanner: DataScannerViewController?
        private var texts = Set<String>()
        private var barcode: (String, BarcodeFormat)?
        private var finished = false

        init(onResult: @escaping (Scan) -> Void) { self.onResult = onResult }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            take(allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate items: [RecognizedItem], allItems: [RecognizedItem]) {
            take(allItems)
        }

        private func take(_ items: [RecognizedItem]) {
            guard !finished else { return }
            var newText = false
            for item in items {
                switch item {
                case .text(let text):
                    if texts.count < 400, texts.insert(text.transcript).inserted { newText = true }
                case .barcode(let code):
                    guard barcode == nil, let payload = code.payloadStringValue, !payload.isEmpty else { continue }
                    barcode = (payload, ImageCodeReader.format(for: code.observation.symbology, payload: payload))
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await finishSoon() }
                @unknown default:
                    break
                }
            }
            // Store recognised while the barcode is in view: done at once.
            if barcode != nil, newText, StoreTemplates.match(in: texts.joined(separator: "\n")) != nil {
                Task { await finish() }
            }
        }

        /// Gives the camera a moment to read the name on the card.
        private func finishSoon() async {
            try? await Task.sleep(for: .milliseconds(1200))
            await finish()
        }

        private func finish() async {
            guard !finished, let code = barcode else { return }
            let (payload, format) = code
            finished = true
            var template = StoreTemplates.match(in: texts.joined(separator: "\n"))
            if template == nil, let photo = try? await scanner?.capturePhoto(), let cg = photo.cgImage {
                template = await Self.readStore(in: cg)
            }
            scanner?.stopScanning()
            UINotificationFeedbackGenerator().notificationOccurred(template == nil ? .warning : .success)
            onResult(Scan(payload: payload, format: format, template: template))
        }

        /// Text recognition on a still photo of the card (sharper than the live view, reads logos with words).
        nonisolated static func readStore(in image: CGImage) async -> StoreTemplate? {
            await Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["nl-NL", "en-US"]
                request.usesLanguageCorrection = false
                try? VNImageRequestHandler(cgImage: image).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(3).map(\.string).joined(separator: "\n") }
                    .joined(separator: "\n")
                return StoreTemplates.match(in: text)
            }.value
        }
    }
}
