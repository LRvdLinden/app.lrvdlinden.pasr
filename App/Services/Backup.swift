import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import CommonCrypto
import Security

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
        var places: [CardPlace]?
        var history: [CardEvent]?
        var balanceURL: String?
    }

    init(cards: [Card]) {
        self.cards = cards.filter { $0.deletedAt == nil }.map { c in
            BackupCard(id: c.id, kind: c.kindRaw, storeName: c.storeName, templateID: c.templateID, number: c.number,
                       format: c.formatRaw, colorHex: c.colorHex, note: c.note, isFavorite: c.isFavorite,
                       isLocked: c.isLocked, useCount: c.useCount, lastUsed: c.lastUsed, createdAt: c.createdAt,
                       balance: c.balance, currencyCode: c.currencyCode, pin: c.pin, expiresAt: c.expiresAt,
                       website: c.website, logoFromWebsite: c.logoFromWebsite, logo: c.logoData,
                       front: c.frontPhoto, back: c.backPhoto, places: c.places.isEmpty ? nil : c.places,
                       history: c.history.isEmpty ? nil : c.history, balanceURL: c.balanceURL)
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
            card.places = b.places ?? []
            card.history = b.history ?? []
            card.balanceURL = b.balanceURL
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


/// Password protection for backup files: AES-256-GCM with a key derived from the password
/// (PBKDF2-SHA256, 310,000 rounds, random salt). Without the password the file can't be read,
/// and Pasr can't recover a forgotten password.
enum BackupCrypto {
    struct Envelope: Codable {
        var format = "pasr-encrypted-backup"
        var version = 1
        var kdf = "pbkdf2-sha256"
        var iterations: Int
        var salt: String
        var data: String
    }

    enum Failure: Error { case wrongPassword, notABackup }

    static let iterations = 310_000

    static func isEncrypted(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(Envelope.self, from: data))?.format == "pasr-encrypted-backup"
    }

    static func encrypt(_ plain: Data, password: String) throws -> Data {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else { throw Failure.notABackup }
        let envelope = Envelope(iterations: iterations, salt: salt.base64EncodedString(),
                                data: combined.base64EncodedString())
        return try JSONEncoder().encode(envelope)
    }

    static func decrypt(_ data: Data, password: String) throws -> Data {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let salt = Data(base64Encoded: envelope.salt),
              let combined = Data(base64Encoded: envelope.data) else { throw Failure.notABackup }
        let key = try deriveKey(password: password, salt: salt, iterations: envelope.iterations)
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key)
        } catch {
            throw Failure.wrongPassword
        }
    }

    private static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        var derived = Data(count: 32)
        let passwordData = Data(password.utf8)
        let status = derived.withUnsafeMutableBytes { out in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { pw in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         pw.bindMemory(to: Int8.self).baseAddress, passwordData.count,
                                         saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                         out.bindMemory(to: UInt8.self).baseAddress, 32)
                }
            }
        }
        guard status == kCCSuccess else { throw Failure.notABackup }
        return SymmetricKey(data: derived)
    }
}

extension BackupDocument {
    /// The backup, encrypted with `password` when one is given.
    init(backup: PasrBackup, password: String?) throws {
        try self.init(backup: backup)
        if let password, !password.isEmpty {
            data = try BackupCrypto.encrypt(data, password: password)
        }
    }

    static func readData(_ url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    static func decode(_ data: Data, password: String?) throws -> PasrBackup {
        let plain = BackupCrypto.isEncrypted(data) ? try BackupCrypto.decrypt(data, password: password ?? "") : data
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(PasrBackup.self, from: plain) else { throw BackupCrypto.Failure.notABackup }
        return backup
    }
}

/// Asks for a password before making a backup file. Encryption is on by default.
struct BackupPasswordSheet: View {
    var onDone: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var encrypt = true
    @State private var password = ""
    @State private var repeatPassword = ""

    private var valid: Bool { !encrypt || (password.count >= 8 && password == repeatPassword) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Versleutel met een wachtwoord", isOn: $encrypt.animation())
                    if encrypt {
                        SecureField("Wachtwoord (minstens 8 tekens)", text: $password)
                            .textContentType(.newPassword)
                        SecureField("Herhaal wachtwoord", text: $repeatPassword)
                            .textContentType(.newPassword)
                    }
                } footer: {
                    if encrypt {
                        Text(!repeatPassword.isEmpty && password != repeatPassword
                             ? String(localized: "De wachtwoorden zijn niet gelijk.")
                             : String(localized: "Zonder dit wachtwoord kan niemand de back-up openen, ook Pasr niet. Bewaar het goed: een vergeten wachtwoord kan niet worden hersteld."))
                    } else {
                        Text("Zonder wachtwoord kan iedereen die het bestand heeft je kaarten lezen.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Back-up maken")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verder") {
                        onDone(encrypt ? password : nil)
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
        }
    }
}
