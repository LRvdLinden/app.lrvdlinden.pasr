import SwiftUI
import SwiftData
import PhotosUI
#if canImport(UIKit)
import UIKit
import VisionKit
#endif

// MARK: - Scannen en controleren

/// Een kassabon scannen (documentscanner van iOS), totaal en datum lokaal laten lezen, controleren en bewaren. Bij een
/// gebruiksmoment (useID) komt de bon bij dat moment; zonder kaart kies je zelf de winkel.
struct ReceiptScanFlow: View {
    let card: Card?
    let useID: UUID?
    var onSaved: ((Double?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var pages: [UIImage] = []
    @State private var reading = false
    @State private var read: ReceiptReader.Result?
    @State private var showScanner = true
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        Group {
            if pages.isEmpty {
                start
            } else {
                ReceiptReviewForm(card: card, useID: useID, pages: pages, read: read, reading: reading) { total in
                    onSaved?(total)
                    dismiss()
                }
            }
        }
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showScanner) {
            if VNDocumentCameraViewController.isSupported {
                DocumentScanner { images in
                    showScanner = false
                    if !images.isEmpty { use(images) }
                } onCancel: {
                    showScanner = false
                }
                .ignoresSafeArea()
            } else {
                Color.clear.onAppear { showScanner = false }
            }
        }
        #endif
        .onChange(of: pickerItems) { _, items in
            Task {
                var images: [UIImage] = []
                for item in items.prefix(Receipt.maxPages) {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { images.append(img) }
                }
                pickerItems = []
                if !images.isEmpty { use(images) }
            }
        }
    }

    /// Als de scanner dicht is zonder bon: opnieuw scannen of een foto kiezen.
    private var start: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "doc.viewfinder").font(.system(size: 54)).foregroundStyle(Brand.iris)
                Text("Kassabon bewaren").font(.title2.weight(.bold))
                Text("Leg de bon plat neer met wat licht erop. Pasr leest het totaal en de datum op je iPhone; je controleert ze daarna zelf.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                #if canImport(UIKit)
                if VNDocumentCameraViewController.isSupported {
                    Button { showScanner = true } label: {
                        Label("Bon scannen", systemImage: "camera.viewfinder").frame(maxWidth: 260).padding(.vertical, 6)
                    }
                    .pasrGlassButton(prominent: true)
                    .tint(Brand.iris)
                }
                #endif
                PhotosPicker(selection: $pickerItems, maxSelectionCount: Receipt.maxPages, matching: .images) {
                    Label("Kies een foto", systemImage: "photo.on.rectangle").frame(maxWidth: 260).padding(.vertical, 6)
                }
                .pasrGlassButton()
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Brand.ink.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer", systemImage: "xmark") { dismiss() } }
            }
        }
    }

    private func use(_ images: [UIImage]) {
        pages = Array(images.prefix(Receipt.maxPages))
        reading = true
        Task {
            let result = await ReceiptReader.read(pages)
            read = result
            reading = false
        }
    }
}

#if canImport(UIKit)
/// De documentscanner van iOS (VisionKit): recht trekken, bijsnijden en meerdere pagina's.
struct DocumentScanner: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onScan((0..<min(scan.pageCount, Receipt.maxPages)).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.onCancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.onCancel() }
    }
}
#endif

/// Totaal, datum, winkel en garantie controleren en de bon bewaren (of een bestaande bon wijzigen).
struct ReceiptReviewForm: View {
    let card: Card?
    let useID: UUID?
    let pages: [UIImage]
    let read: ReceiptReader.Result?
    let reading: Bool
    var onSaved: (Double?) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @State private var cardID: UUID?
    @State private var store = ""
    @State private var date = Date()
    @State private var totalText = ""
    @State private var title = ""
    @State private var hasWarranty = false
    @State private var warranty = Receipt.defaultWarranty(from: .now)
    @State private var filled = false

    private var total: Double? { PurchaseCapture.parseAmount(totalText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(pages.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img).resizable().scaledToFit()
                                    .frame(height: 170)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .accessibilityLabel(Text("Gescande bon"))
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    if reading {
                        Label("Totaal en datum lezen…", systemImage: "text.viewfinder").foregroundStyle(.secondary)
                    }
                }
                Section {
                    if card == nil {
                        Picker("Kaart", selection: $cardID) {
                            Text("Geen kaart").tag(UUID?.none)
                            ForEach(cards.alphabetical()) { c in Text(c.storeName).tag(Optional(c.id)) }
                        }
                        .onChange(of: cardID) { _, id in
                            if let c = cards.first(where: { $0.id == id }) { store = c.storeName }
                        }
                    }
                    TextField("Winkel", text: $store)
                    HStack {
                        Text("Totaal")
                        Spacer()
                        Text("€").foregroundStyle(.secondary)
                        TextField("0,00", text: $totalText)
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(maxWidth: 120)
                            .accessibilityLabel(Text("Totaal in euro"))
                    }
                    DatePicker("Datum", selection: $date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: .date)
                    TextField("Wat kocht je? (optioneel)", text: $title)
                } header: {
                    Text("Controleer de bon")
                } footer: {
                    Text(read == nil && !reading ? "" : "Pasr las het totaal en de datum op je iPhone. Klopt iets niet, pas het dan aan.")
                }
                Section {
                    Toggle("Garantie bijhouden", isOn: $hasWarranty)
                    if hasWarranty {
                        DatePicker("Garantie tot", selection: $warranty, in: date..., displayedComponents: .date)
                        HStack(spacing: 8) {
                            ForEach([1, 2, 3, 5], id: \.self) { years in
                                Button("\(years) jaar") {
                                    warranty = Calendar.current.date(byAdding: .year, value: years, to: date) ?? warranty
                                }
                                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                            }
                        }
                    }
                } footer: {
                    Text("Een maand voordat de garantie afloopt, krijg je een herinnering. De bon blijft op je apparaten en in je iCloud, net als de foto's van een pas.")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Bonnetje")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar", systemImage: "checkmark") { save() }
                        .disabled(store.trimmingCharacters(in: .whitespaces).isEmpty || (!totalText.isEmpty && total == nil))
                }
            }
            .onAppear {
                if !filled {
                    filled = true
                    cardID = card?.id
                    store = card?.storeName ?? ""
                    if let e = card?.history.first(where: { $0.id == useID }) { date = e.date }
                    apply(read)
                }
            }
            .onChange(of: read) { _, r in apply(r) }
            .onChange(of: date) { _, d in if !hasWarranty { warranty = Receipt.defaultWarranty(from: d) } }
        }
    }

    private func apply(_ r: ReceiptReader.Result?) {
        guard let r else { return }
        // Alleen een duidelijke overeenkomst als kaart voorstellen. Gebruiker controleert de bon.
        if card == nil, cardID == nil, !r.text.isEmpty {
            let merchant = r.text.prefix(12).joined(separator: " ")
            if let match = PurchaseMatcher.best(merchant: merchant, among: cards) {
                cardID = match.id
                store = match.storeName
            }
        }
        if totalText.isEmpty, let t = r.total {
            totalText = t.formatted(.number.precision(.fractionLength(2)).locale(UseFormat.locale))
        }
        if let d = r.date, useID == nil || abs(d.timeIntervalSince(date)) > 86_400 * 2 {
            date = d
        }
        warranty = Receipt.defaultWarranty(from: date)
    }

    private func save() {
        // OCR kan de winkel herkennen zonder dat al een kaart geselecteerd is.
        // Gebruik alleen een eenduidig passende kaart; bij meerdere gelijknamige kaarten
        // blijft de keuze bij de gebruiker.
        let inferred: Card? = {
            guard card == nil, cardID == nil else { return nil }
            let exact = cards.filter {
                $0.storeName.compare(store.trimmingCharacters(in: .whitespacesAndNewlines),
                                     options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            return exact.count == 1 ? exact.first : nil
        }()
        let linked = card ?? cards.first(where: { $0.id == cardID }) ?? inferred
        let r = Receipt(cardID: linked?.id, useID: nil, storeName: store.trimmingCharacters(in: .whitespaces), date: date)
        r.total = total
        r.currencyCode = linked?.currencyCode
        r.title = title.trimmingCharacters(in: .whitespaces)
        r.warrantyUntil = hasWarranty ? Calendar.current.startOfDay(for: warranty) : nil
        r.pages = pages.compactMap { $0.jpegData(compressionQuality: 0.85).flatMap { ImageResizer.jpeg($0, maxSide: 2000, quality: 0.78) } }
        context.insert(r)
        if let linked {
            ReceiptUseLinker.attach(r, to: linked, preferredUse: useID)
        }
        try? context.save()
        Task { await ReceiptReminders.schedule(r) }
        onSaved(total)
    }
}

/// Eén kassabon is een aantoonbare winkeltransactie, ook wanneer de klant de kaart niet scande.
/// Koppel eerst aan een passend, nog bonloos gebruiksmoment. Maak anders een nieuw moment.
/// Voor cadeaukaarten wordt NOOIT automatisch tegoed afgeboekt door een kassabon.
@MainActor
enum ReceiptUseLinker {
    static func attach(_ receipt: Receipt, to card: Card, preferredUse: UUID? = nil) {
        guard receipt.cardID == card.id else { return }
        // Ook herhaald openen/herstellen blijft idempotent.
        if let linked = card.uses.first(where: { $0.receiptID == receipt.id }) {
            receipt.useID = linked.id
            if linked.source == "receipt" {
                // Handmatig gecorrigeerde bon: bijbehorend automatisch moment volgt mee.
                card.updateUse(linked.id) { event in
                    event.date = receipt.date
                    event.amount = receipt.total.flatMap { $0 > 0 ? $0 : nil }
                }
            }
            return
        }
        let candidates = card.uses.filter {
            $0.receiptID == nil && Calendar.current.isDate($0.date, inSameDayAs: receipt.date)
        }
        let amountMatches = candidates.filter { event in
            guard let total = receipt.total, total > 0 else { return false }
            return [event.amount, event.pendingAmount].compactMap { $0 }
                .contains { abs($0 - total) <= 0.02 }
        }
        // Bij meerdere mogelijkheden kies het dichtstbijzijnde moment. Zonder bedrag
        // alleen automatisch koppelen als er precies één mogelijke scan op de dag is.
        let unknownAmount = candidates.filter { $0.amount == nil && $0.pendingAmount == nil }
        let matched = preferredUse.flatMap { id in
            candidates.first(where: { $0.id == id })
        } ?? amountMatches.min(by: {
            abs($0.date.timeIntervalSince(receipt.date)) < abs($1.date.timeIntervalSince(receipt.date))
        }) ?? (unknownAmount.count == 1 ? unknownAmount.first : nil)
        let eventID: UUID
        if let matched {
            eventID = matched.id
        } else {
            var event = CardEvent(kind: .shown)
            event.date = receipt.date
            event.source = "receipt"
            var history = card.history
            history.insert(event, at: 0)
            card.history = history
            // Geschiedenis bewaart standaard 90 dagen: voor zeer oude bonnetjes
            // is er geen bewaard gebruiksmoment meer om aan te koppelen.
            guard card.uses.contains(where: { $0.id == event.id }) else { return }
            eventID = event.id
        }
        receipt.useID = eventID
        card.updateUse(eventID) { event in
            event.receiptID = receipt.id
            if event.amount == nil, let total = receipt.total, total > 0 {
                // Bedrag tonen onder Laatst gebruikt. Dit is geen bewijs dat de
                // klant met de cadeaukaart heeft afgerekend: saldo niet aanpassen.
                event.amount = total
                event.pendingAmount = nil
            }
        }
    }

    static func reconcile(_ receipts: [Receipt], cards: [Card], context: ModelContext) {
        var changed = false
        for receipt in receipts {
            let card: Card? = {
                if let cardID = receipt.cardID {
                    return cards.first(where: { $0.id == cardID && $0.deletedAt == nil })
                }
                // Herstel ook oude bonnen waarbij OCR wel 'Action' herkende maar
                // er nog geen kaart was vastgelegd. Alleen bij exact één winkelkaart.
                guard receipt.total != nil else { return nil }
                let sameStore = cards.filter {
                    $0.deletedAt == nil &&
                    $0.storeName.compare(receipt.storeName,
                        options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
                return sameStore.count == 1 ? sameStore.first : nil
            }()
            guard let card else { continue }
            if receipt.cardID == nil { receipt.cardID = card.id }
            let correctlyLinked = receipt.useID.flatMap { id in
                card.uses.first(where: { $0.id == id && $0.receiptID == receipt.id })
            } != nil
            if correctlyLinked { continue }
            attach(receipt, to: card)
            if receipt.useID != nil { changed = true }
        }
        if changed { try? context.save() }
    }
}

// MARK: - Overzicht

/// Alle bonnetjes van alle kaarten, nieuwste eerst; zoeken op winkel, bedrag of datum, en "Garantie loopt nog".
struct ReceiptsView: View {
    var initialQuery = ""
    /// In Instellingen (al in een NavigationStack): zonder eigen NavigationStack en knop Klaar.
    var embedded = false

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @State private var query = ""
    @State private var onlyWarranty = false
    @State private var cardFilter: UUID?
    @State private var scanning = false
    @State private var open: Receipt?

    private var visible: [Receipt] {
        receipts.filter { r in
            (!onlyWarranty || r.warrantyActive) && (cardFilter == nil || r.cardID == cardFilter) && r.matches(query)
        }
    }

    private struct ReceiptGroup: Identifiable {
        let title: String
        var items: [Receipt]
        var id: String { title }
    }

    private var groups: [ReceiptGroup] {
        var out: [ReceiptGroup] = []
        for r in visible {
            let title = UseFormat.group(r.date)
            if out.last?.title == title { out[out.count - 1].items.append(r) } else { out.append(ReceiptGroup(title: title, items: [r])) }
        }
        return out
    }

    var body: some View {
        if embedded { content } else { NavigationStack { content } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                filters
                if visible.isEmpty {
                    ContentUnavailableView {
                        Label(receipts.isEmpty ? "Nog geen bonnetjes" : "Geen bonnetjes gevonden", systemImage: "doc.text")
                    } description: {
                        Text(receipts.isEmpty
                             ? "Scan de kassabon van een aankoop, bij een kaart of los. Met de datum Garantie tot krijg je een herinnering voordat de garantie afloopt."
                             : "Zoek op winkel, bedrag (12,50) of datum (12 november).")
                    } actions: {
                        Button { scanning = true } label: { Label("Bon scannen", systemImage: "doc.viewfinder") }
                            .pasrGlassButton(prominent: true).tint(Brand.iris)
                    }
                    .padding(.top, 20)
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title.uppercased(with: UseFormat.locale))
                            .font(.footnote.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityLabel(Text(group.title))
                        UsesPanel {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { i, r in
                                Button { open = r } label: { ReceiptRow(receipt: r, card: cards.first { $0.id == r.cardID }) }
                                    .buttonStyle(.plain)
                                if i < group.items.count - 1 { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Brand.ink.ignoresSafeArea())
        .navigationTitle("Bonnetjes")
        .searchable(text: $query, prompt: Text("Winkel, bedrag of datum"))
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .cancellationAction) { Button("Klaar", systemImage: "checkmark") { dismiss() } }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { scanning = true } label: { Label("Bon scannen", systemImage: "doc.viewfinder") }
            }
        }
        .sheet(isPresented: $scanning) {
            ReceiptScanFlow(card: cardFilter.flatMap { id in cards.first { $0.id == id } }, useID: nil)
        }
        .sheet(item: $open) { r in ReceiptDetailView(receipt: r) }
        .onAppear { if query.isEmpty { query = initialQuery } }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(String(localized: "Alles"), on: !onlyWarranty && cardFilter == nil) { onlyWarranty = false; cardFilter = nil }
                chip(String(localized: "Garantie loopt nog"), symbol: "checkmark.shield", on: onlyWarranty) { onlyWarranty.toggle() }
                let withReceipts = cards.filter { c in receipts.contains { $0.cardID == c.id } }.alphabetical()
                ForEach(withReceipts) { c in
                    chip(c.storeName, on: cardFilter == c.id) { cardFilter = cardFilter == c.id ? nil : c.id }
                }
            }
            .padding(.top, 4)
        }
    }

    private func chip(_ title: String, symbol: String? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() } }) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(on ? AnyShapeStyle(Brand.iris) : AnyShapeStyle(Brand.inkRaised), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Een regel: miniatuur, winkel (en wat je kocht), datum, garantie en het bedrag.
struct ReceiptRow: View {
    let receipt: Receipt
    var card: Card? = nil

    var body: some View {
        HStack(spacing: 12) {
            ReceiptThumb(receipt: receipt, size: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text(receipt.title.isEmpty ? receipt.storeName : "\(receipt.storeName) · \(receipt.title)")
                    .font(.body.weight(.bold)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(receipt.date.formatted(.dateTime.day().month(.wide).year().locale(UseFormat.locale)))
                    if let w = receipt.warrantyUntil {
                        Text("·")
                        Label(receipt.warrantyActive
                              ? String(localized: "garantie tot \(w.formatted(.dateTime.day().month(.abbreviated).year().locale(UseFormat.locale)))")
                              : String(localized: "garantie verlopen"),
                              systemImage: receipt.warrantyActive ? "checkmark.shield.fill" : "shield.slash")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.footnote).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let t = receipt.total {
                Text(CardHistoryFormat.money(t, receipt.currencyCode))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Kleine kaart in de zoekresultaten op het hoofdscherm.
struct ReceiptChip: View {
    let receipt: Receipt
    var body: some View {
        HStack(spacing: 8) {
            ReceiptThumb(receipt: receipt, size: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(receipt.storeName).font(.footnote.weight(.bold)).lineLimit(1)
                Text([receipt.date.formatted(.dateTime.day().month(.abbreviated).locale(UseFormat.locale)),
                      receipt.total.map { CardHistoryFormat.money($0, receipt.currencyCode) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(8)
        .background(Brand.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ReceiptThumb: View {
    let receipt: Receipt
    let size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(Color.white)
            .frame(width: size, height: size)
            .overlay {
                if let data = receipt.page1, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipped()
                } else {
                    Image(systemName: "doc.text").foregroundStyle(.gray)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

// MARK: - Eén bon

/// Groot tonen met inzoomen, delen als PDF of afbeelding (voor een garantieclaim), wijzigen en verwijderen.
struct ReceiptDetailView: View {
    @Bindable var receipt: Receipt
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @State private var page = 0
    @State private var share: ActivityItems?
    @State private var confirmDelete = false
    @State private var editing = false

    private var images: [UIImage] { receipt.pages.compactMap(UIImage.init(data:)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                        ZoomableImage(image: img)
                            .tag(i)
                            .accessibilityLabel(Text("Bon, pagina \(i + 1) van \(images.count)"))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
                .background(Color.black)
                info
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle(receipt.storeName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Klaar", systemImage: "checkmark") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { share = ActivityItems(items: [ReceiptExport.pdf(receipt)].compactMap { $0 }) } label: {
                            Label("Deel als PDF", systemImage: "doc.richtext")
                        }
                        Button { share = ActivityItems(items: ReceiptExport.images(receipt)) } label: {
                            Label("Deel als afbeelding", systemImage: "photo")
                        }
                    } label: { Label("Deel", systemImage: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { editing = true } label: { Label("Wijzig", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Verwijder", systemImage: "trash") }
                    } label: { Label("Meer", systemImage: "ellipsis.circle") }
                }
            }
            .sheet(item: $share) { item in ActivityView(items: item.items).presentationDetents([.medium, .large]) }
            .sheet(isPresented: $editing) { ReceiptEditSheet(receipt: receipt) }
            .confirmationDialog("Dit bonnetje verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Verwijder", role: .destructive) { delete() }
            } message: {
                Text("De bon en de garantieherinnering verdwijnen van al je apparaten.")
            }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(receipt.title.isEmpty ? receipt.storeName : receipt.title).font(.headline)
                    Text(receipt.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(UseFormat.locale)))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let t = receipt.total {
                    Text(CardHistoryFormat.money(t, receipt.currencyCode)).font(.title3.weight(.heavy).monospacedDigit())
                }
            }
            if let w = receipt.warrantyUntil {
                Label(receipt.warrantyActive
                      ? String(localized: "Garantie tot \(w.formatted(.dateTime.day().month(.wide).year().locale(UseFormat.locale)))")
                      : String(localized: "Garantie verlopen op \(w.formatted(.dateTime.day().month(.wide).year().locale(UseFormat.locale)))"),
                      systemImage: receipt.warrantyActive ? "checkmark.shield.fill" : "shield.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(receipt.warrantyActive ? Brand.mint : .secondary)
            }
            if !receipt.note.isEmpty { Text(receipt.note).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.inkRaised)
    }

    private func delete() {
        ReceiptReminders.cancel(receipt)
        let id = receipt.id
        if let cardID = receipt.cardID, let useID = receipt.useID, let card = cards.first(where: { $0.id == cardID }) {
            if let event = card.uses.first(where: { $0.id == useID && $0.receiptID == id }),
               event.source == "receipt" {
                // Een uitsluitend vanuit de bon aangemaakt gebruiksmoment ook verwijderen.
                card.history = card.history.filter { $0.id != useID }
            } else {
                card.updateUse(useID) { if $0.receiptID == id { $0.receiptID = nil } }
            }
        }
        context.delete(receipt)
        try? context.save()
        dismiss()
    }
}

/// Winkel, datum, totaal, wat je kocht, notitie en garantie van een bewaarde bon aanpassen.
struct ReceiptEditSheet: View {
    @Bindable var receipt: Receipt
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var store = ""
    @State private var date = Date()
    @State private var totalText = ""
    @State private var title = ""
    @State private var note = ""
    @State private var hasWarranty = false
    @State private var warranty = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Winkel", text: $store)
                    HStack {
                        Text("Totaal")
                        Spacer()
                        TextField("0,00", text: $totalText).multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .frame(maxWidth: 120)
                    }
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    TextField("Wat kocht je?", text: $title)
                    TextField("Notitie", text: $note, axis: .vertical)
                }
                Section {
                    Toggle("Garantie bijhouden", isOn: $hasWarranty)
                    if hasWarranty { DatePicker("Garantie tot", selection: $warranty, in: date..., displayedComponents: .date) }
                }
            }
            .navigationTitle("Bonnetje wijzigen")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar", systemImage: "checkmark") { save() }
                        .disabled(store.trimmingCharacters(in: .whitespaces).isEmpty
                                  || (!totalText.isEmpty && PurchaseCapture.parseAmount(totalText) == nil))
                }
            }
            .onAppear {
                store = receipt.storeName
                date = receipt.date
                totalText = receipt.total.map { $0.formatted(.number.precision(.fractionLength(2)).locale(UseFormat.locale)) } ?? ""
                title = receipt.title
                note = receipt.note
                hasWarranty = receipt.warrantyUntil != nil
                warranty = receipt.warrantyUntil ?? Receipt.defaultWarranty(from: receipt.date)
            }
        }
    }

    private func save() {
        receipt.storeName = store.trimmingCharacters(in: .whitespaces)
        receipt.date = date
        receipt.total = totalText.isEmpty ? nil : PurchaseCapture.parseAmount(totalText)
        receipt.title = title.trimmingCharacters(in: .whitespaces)
        receipt.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        receipt.warrantyUntil = hasWarranty ? Calendar.current.startOfDay(for: warranty) : nil
        receipt.updatedAt = .now
        try? context.save()
        let r = receipt
        Task { await ReceiptReminders.schedule(r) }
        dismiss()
    }
}

#if canImport(UIKit)
/// Foto met knijpen om in te zoomen en schuiven (UIScrollView), dubbeltik om in of uit te zoomen.
struct ZoomableImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 6
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .black
        scroll.delegate = context.coordinator
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = true
        view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(view)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        ])
        context.coordinator.imageView = view
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(tap)
        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let scroll = g.view as? UIScrollView else { return }
            if scroll.zoomScale > 1 { scroll.setZoomScale(1, animated: true); return }
            let point = g.location(in: imageView)
            let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
            scroll.zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size), animated: true)
        }
    }
}

/// Een bon als PDF (alle pagina's, A4-breedte) of als afbeeldingen, in een tijdelijk bestand om te delen.
enum ReceiptExport {
    private static func fileName(_ r: Receipt, ext: String) -> String {
        let day = r.date.formatted(.iso8601.year().month().day())
        let base = "Bon \(r.storeName) \(day)".components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        return "\(base).\(ext)"
    }

    static func pdf(_ r: Receipt) -> URL? {
        let images = r.pages.compactMap(UIImage.init(data:))
        guard !images.isEmpty else { return nil }
        let pageWidth: CGFloat = 595   // A4 in punten
        let url = FileManager.default.temporaryDirectory.appending(path: fileName(r, ext: "pdf"))
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: 842))
        do {
            try renderer.writePDF(to: url) { ctx in
                for img in images {
                    let height = pageWidth * img.size.height / max(img.size.width, 1)
                    let bounds = CGRect(x: 0, y: 0, width: pageWidth, height: max(height, 200))
                    ctx.beginPage(withBounds: bounds, pageInfo: [:])
                    img.draw(in: CGRect(x: 0, y: 0, width: pageWidth, height: height))
                }
            }
            return url
        } catch { return nil }
    }

    static func images(_ r: Receipt) -> [Any] {
        r.pages.enumerated().compactMap { i, data in
            let url = FileManager.default.temporaryDirectory.appending(path: fileName(r, ext: r.pages.count > 1 ? "\(i + 1).jpg" : "jpg"))
            return (try? data.write(to: url)) != nil ? url : nil
        }
    }
}
#endif
