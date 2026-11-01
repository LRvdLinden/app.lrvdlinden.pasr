import SwiftUI
import SwiftData
import PhotosUI

/// Bulk import from screenshots, e.g. of every card in the Klarna app.
/// Each screenshot is read on the device; you check the list, then import.
struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var items: [PhotosPickerItem] = []
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
    }

    @State private var cropRequest: CropRequest?

    var body: some View {
        NavigationStack {
            Group {
                if found.isEmpty && progress == nil {
                    intro
                } else {
                    results
                }
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Screenshots importeren")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                if !found.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Importeer \(found.filter(\.include).count)") { importCards() }
                            .disabled(found.allSatisfy { !$0.include } || progress != nil)
                    }
                }
            }
            .onChange(of: items) { _, newItems in Task { await read(newItems) } }
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
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Brand.gradient)
            Text("Neem je kaarten mee").font(.title2.bold())
            VStack(alignment: .leading, spacing: 10) {
                step(1, "Open Klarna (of een andere kaarten-app) en maak van elke kaart een screenshot met de barcode.")
                step(2, "Kies die screenshots hier, tot 50 tegelijk.")
                step(3, "Pasr vindt de barcode en de winkel. Controleer de lijst en importeer.")
            }
            .padding(.horizontal, 28)
            PhotosPicker(selection: $items, maxSelectionCount: 50, matching: .screenshots) {
                Label("Kies screenshots", systemImage: "photo.on.rectangle").frame(maxWidth: 260).padding(.vertical, 6)
            }
            .pasrGlassButton(prominent: true)
            .tint(Brand.iris)
            PhotosPicker(selection: $items, maxSelectionCount: 50, matching: .images) {
                Text("Kies uit alle foto's")
            }
            .font(.footnote)
            Text("Alles wordt op je apparaat gelezen. Er wordt niets geüpload.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Spacer()
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
            // A logo cut from a Klarna/Stocard screenshot of a known store makes way for the store's own logo.
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
