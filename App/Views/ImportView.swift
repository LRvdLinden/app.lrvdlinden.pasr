import SwiftUI
import SwiftData
import PhotosUI

/// Kaarten overnemen uit een andere app (zoals Klarna): met een schermopname waarin je langs je kaarten gaat, of met
/// screenshots. Alles wordt op het apparaat gelezen; je controleert de lijst en importeert.
/// Een telefoon die opneemt (rode stip) terwijl kaarten voorbij schuiven en één voor één in Pasr landen.
private struct RecordingArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                    .frame(width: 92, height: 150)
                ForEach(0..<3) { i in
                    let p = (phase + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill([Brand.mint, Brand.coral, Brand.iris][i].gradient)
                        .frame(width: 70, height: 44)
                        .offset(y: 70 - p * 140)
                        .opacity(p < 0.1 ? p * 10 : p > 0.9 ? (1 - p) * 10 : 1)
                }
                .mask(RoundedRectangle(cornerRadius: 20).frame(width: 88, height: 146))
                Circle().fill(.red).frame(width: 10, height: 10)
                    .opacity(phase.truncatingRemainder(dividingBy: 0.5) < 0.25 ? 1 : 0.3)
                    .offset(x: 32, y: -62)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var items: [PhotosPickerItem] = []
    @State private var video: PhotosPickerItem?
    @State private var videoProgress: Double?
    @State private var found: [Found] = []
    @State private var failed = 0
    @State private var progress: (done: Int, total: Int)?

    struct Found: Identifiable {
        let id = UUID()
        var include = true
        var storeName: String
        var number: String
        var format: BarcodeFormat
        var colorHex: String
        var templateID: String?
        var kind: CardKind
        var imageData: Data?
        var logoData: Data?
        // uit een bestand (CSV, JSON, .pkpass)
        var balance: Double? = nil
        var expiresAt: Date? = nil
        var note: String = ""
        var details: CardDetails? = nil
    }

    @State private var pickingFile = false
    @State private var fileMessage: String?

    @State private var cropRequest: CropRequest?

    var body: some View {
        NavigationStack {
            Group {
                if found.isEmpty && progress == nil && videoProgress == nil {
                    intro
                } else {
                    results
                }
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Kaarten importeren")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer", systemImage: "xmark") { dismiss() } }
                if !found.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Importeer \(found.filter(\.include).count)", systemImage: "square.and.arrow.down") { importCards() }
                            .disabled(found.allSatisfy { !$0.include } || progress != nil || videoProgress != nil)
                    }
                }
            }
            .onChange(of: items) { _, newItems in Task { await read(newItems) } }
            .onChange(of: video) { _, item in Task { await readVideo(item) } }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: WalletImport.fileTypes, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { readFiles(urls) }
            }
            .sheet(item: $cropRequest) { request in
                if let cropper = LogoCropperView(imageData: request.data, onCrop: { png in
                    if let index = found.firstIndex(where: { $0.id == request.target }) { found[index].logoData = png }
                }) {
                    cropper
                }
            }
        }
    }

    private var intro: some View {
        ScrollView {
            VStack(spacing: 20) {
                RecordingArt()
                    .frame(height: 150)
                    .padding(.top, 10)
                Text("Neem je kaarten mee").font(.title2.bold())
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Zet Schermopname aan in het Bedieningspaneel en open Klarna (of een andere kaarten-app).")
                    step(2, "Tik rustig op je kaarten, één voor één, zodat elke barcode even in beeld is. Stop de opname.")
                    step(3, "Kies de opname hier. Pasr vindt de barcodes en de winkels; jij controleert de lijst.")
                }
                .padding(.horizontal, 28)
                PhotosPicker(selection: $video, matching: .videos) {
                    Label("Kies schermopname", systemImage: "record.circle").frame(maxWidth: 260).padding(.vertical, 6)
                }
                .pasrGlassButton(prominent: true)
                .tint(Brand.iris)
                PhotosPicker(selection: $items, maxSelectionCount: 50, matching: .screenshots) {
                    Label("Of kies screenshots (tot 50)", systemImage: "photo.on.rectangle").frame(maxWidth: 260).padding(.vertical, 6)
                }
                .pasrGlassButton()
                PhotosPicker(selection: $items, maxSelectionCount: 50, matching: .images) {
                    Text("Kies uit alle foto's")
                }
                .font(.footnote)
                Divider().padding(.horizontal, 40).padding(.vertical, 4)
                Text("Uit een bestand").font(.headline)
                Text("Een CSV- of JSON-export van een andere kaarten-app, een eigen lijst, of een Apple Wallet-pas (.pkpass). Pasr herkent kolommen als naam, nummer, formaat, soort, saldo en vervaldatum.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button { pickingFile = true } label: {
                    Label("Kies bestand", systemImage: "doc.badge.plus").frame(maxWidth: 260).padding(.vertical, 6)
                }
                .pasrGlassButton()
                ShareLink(item: WalletImport.exampleCSV, preview: SharePreview("Voorbeeld voor Pasr (CSV)")) {
                    Label("Voorbeeld-CSV", systemImage: "tablecells")
                }
                .font(.footnote)
                if let fileMessage {
                    Text(fileMessage).font(.footnote).foregroundStyle(Brand.coral)
                        .multilineTextAlignment(.center).padding(.horizontal, 28)
                }
                Text("Alles wordt op je apparaat gelezen. Er wordt niets geüpload.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 30)
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .frame(width: 24, height: 24)
                .background(Brand.iris.opacity(0.25), in: Circle())
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var results: some View {
        List {
            if let videoProgress {
                Section {
                    ProgressView(value: videoProgress) {
                        Text("Schermopname lezen… \(Int(videoProgress * 100))%")
                    }
                    Text("\(found.count) kaarten gevonden").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let progress {
                Section {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                        Text("Screenshots lezen… \(progress.done) van \(progress.total)")
                    }
                }
            }
            if failed > 0 {
                Section {
                    Label("Geen barcode gevonden in \(failed) screenshot(s).", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Gevonden") {
                ForEach($found) { $item in
                    HStack(spacing: 12) {
                        Toggle("", isOn: $item.include).labelsHidden()
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(hex: item.colorHex).gradient)
                            if let logo = item.logoData, let image = Image(data: logo) {
                                image.resizable().scaledToFit().padding(4)
                            } else {
                                Text(String(item.storeName.prefix(2)).uppercased())
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.onCard(item.colorHex))
                            }
                        }
                        .frame(width: 56, height: 56 / Brand.cardAspect)
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Winkel", text: $item.storeName).font(.headline)
                            Text("\(item.format.displayName) · \(item.number)")
                                .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if let data = item.imageData {
                            Button {
                                cropRequest = CropRequest(data: data, target: item.id)
                            } label: {
                                Label("Logo uitknippen", systemImage: "scissors").labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func read(_ selection: [PhotosPickerItem]) async {
        guard !selection.isEmpty else { return }
        progress = (0, selection.count)
        failed = 0
        let existingNumbers = Set((try? context.fetch(FetchDescriptor<Card>()))?.map(\.number) ?? [])
        for (index, item) in selection.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self),
               let result = await ImageCodeReader.read(data) {
                let duplicate = existingNumbers.contains(result.payload) || found.contains { $0.number == result.payload }
                if !duplicate {
                    let template = result.template
                    found.append(Found(storeName: template?.name ?? guessName(from: result.recognizedText),
                                       number: result.payload, format: result.format,
                                       colorHex: template?.cardHex ?? (Brand.palette.randomElement() ?? "#6A5CFF"),
                                       templateID: template?.id, kind: template?.kind ?? .loyalty,
                                       imageData: data))
                }
            } else {
                failed += 1
            }
            progress = (index + 1, selection.count)
        }
        progress = nil
        items = []
    }

    private func readVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        videoProgress = 0
        failed = 0
        defer { videoProgress = nil; video = nil }
        guard let movie = try? await item.loadTransferable(type: VideoCodeReader.Movie.self) else { return }
        let existing = Set((try? context.fetch(FetchDescriptor<Card>()))?.map(\.number) ?? []).union(found.map(\.number))
        await VideoCodeReader.read(movie.url, existing: existing, progress: { videoProgress = $0 }) { hit in
            let result = hit.result
            let template = result.template
            withAnimation(.snappy) {
                found.append(Found(storeName: template?.name ?? guessName(from: result.recognizedText),
                                   number: result.payload, format: result.format,
                                   colorHex: template?.cardHex ?? (Brand.palette.randomElement() ?? "#6A5CFF"),
                                   templateID: template?.id, kind: template?.kind ?? .loyalty,
                                   imageData: hit.frame))
            }
        }
    }

    /// CSV, JSON of .pkpass: lezen en aan de lijst toevoegen (dubbele nummers overgeslagen).
    private func readFiles(_ urls: [URL]) {
        fileMessage = nil
        var existing = Set((try? context.fetch(FetchDescriptor<Card>()))?.map(\.number) ?? []).union(found.map(\.number))
        var errors: [String] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), data.count < 30_000_000 else { errors.append(url.lastPathComponent); continue }
            do {
                for item in try WalletImport.read(data, fileName: url.lastPathComponent) where !existing.contains(item.number) {
                    existing.insert(item.number)
                    let template = StoreTemplates.match(in: item.storeName)
                    let kind = item.kind ?? template?.kind ?? (item.balance != nil ? .voucher : .loyalty)
                    let format = item.format ?? template?.format ?? BarcodeFormat.guess(for: item.number)
                    found.append(Found(storeName: template?.name ?? item.storeName, number: item.number, format: format,
                                       colorHex: template?.cardHex ?? item.colorHex ?? (Brand.palette.randomElement() ?? "#6A5CFF"),
                                       templateID: template?.id, kind: kind, imageData: nil, logoData: item.logo,
                                       balance: item.balance, expiresAt: item.expiresAt, note: item.note, details: item.details))
                }
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if !errors.isEmpty { fileMessage = errors.joined(separator: "\n") }
    }

    /// Without a known store: the first short line of text that isn't a number or a clock.
    private func guessName(from text: String) -> String {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.first { line in
            line.count >= 3 && line.count <= 28 && line.rangeOfCharacter(from: .letters) != nil
                && !line.contains(":") && line.filter(\.isNumber).count < 4
        } ?? String(localized: "Kaart")
    }

    private func importCards() {
        for item in found where item.include {
            let card = Card(storeName: item.storeName, number: item.number, format: item.format,
                            kind: item.kind, colorHex: item.colorHex)
            card.templateID = item.templateID
            card.logoData = item.logoData
            card.balance = item.balance
            if item.balance != nil { card.currencyCode = "EUR" }
            card.expiresAt = item.kind.hasExpiry ? item.expiresAt : nil
            card.note = item.note
            if let details = item.details { card.details = details }
            // A logo cut from a Klarna screenshot of a known store makes way for the store's own logo.
            card.logoFromWebsite = card.templateID != nil
            card.refreshCodeImage()
            context.insert(card)
        }
        try? context.save()
        let context = context
        Task { await LogoService.fillMissing(in: context) }
        dismiss()
    }
}
