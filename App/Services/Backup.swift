import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A complete copy of all cards in one file, including logos and photos, to keep in iCloud Drive
/// or anywhere else, and to restore later. iCloud already syncs your cards; this is the extra copy.
struct PasrBackup: Codable {
    var version = 1
    var createdAt = Date()
    var cards: [BackupCard]

    struct BackupCard: Codable {
        var id: UUID
        var kind: String
        var storeName: String
        var templateID: String?
        var number: String
        var format: String
        var colorHex: String
        var note: String
        var isFavorite: Bool
        var isLocked: Bool
        var useCount: Int
        var lastUsed: Date?
        var createdAt: Date
        var balance: Double?
        var currencyCode: String?
        var pin: String?
        var expiresAt: Date?
        var website: String?
        var logoFromWebsite: Bool
        var logo: Data?
        var front: Data?
        var back: Data?
    }

    init(cards: [Card]) {
        self.cards = cards.filter { $0.deletedAt == nil }.map { c in
            BackupCard(id: c.id, kind: c.kindRaw, storeName: c.storeName, templateID: c.templateID, number: c.number,
                       format: c.formatRaw, colorHex: c.colorHex, note: c.note, isFavorite: c.isFavorite,
                       isLocked: c.isLocked, useCount: c.useCount, lastUsed: c.lastUsed, createdAt: c.createdAt,
                       balance: c.balance, currencyCode: c.currencyCode, pin: c.pin, expiresAt: c.expiresAt,
                       website: c.website, logoFromWebsite: c.logoFromWebsite, logo: c.logoData,
                       front: c.frontPhoto, back: c.backPhoto)
        }
    }

    /// Adds the cards from the backup that aren't in Pasr yet. Returns how many were added.
    @MainActor
    func restore(into context: ModelContext) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let ids = Set(existing.map(\.id))
        let codes = Set(existing.filter { $0.deletedAt == nil }.map { "\($0.formatRaw)|\($0.number)" })
        var added = 0
        for b in cards where !ids.contains(b.id) && !codes.contains("\(b.format)|\(b.number)") {
            let card = Card(storeName: b.storeName, number: b.number,
                            format: BarcodeFormat(rawValue: b.format) ?? .code128,
                            kind: CardKind(rawValue: b.kind) ?? .loyalty, colorHex: b.colorHex)
            card.id = b.id
            card.templateID = b.templateID
            card.note = b.note
            card.isFavorite = b.isFavorite
            card.isLocked = b.isLocked
            card.useCount = b.useCount
            card.lastUsed = b.lastUsed
            card.createdAt = b.createdAt
            card.balance = b.balance
            card.currencyCode = b.currencyCode
            card.pin = b.pin
            card.expiresAt = b.expiresAt
            card.website = b.website
            card.logoFromWebsite = b.logoFromWebsite
            card.logoData = b.logo
            card.frontPhoto = b.front
            card.backPhoto = b.back
            card.refreshCodeImage()
            context.insert(card)
            added += 1
        }
        try? context.save()
        return added
    }
}

/// The backup as a file for `.fileExporter`.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(backup: PasrBackup) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        data = try encoder.encode(backup)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static func read(_ url: URL) throws -> PasrBackup {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PasrBackup.self, from: Data(contentsOf: url))
    }
}
