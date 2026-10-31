import Foundation
import SwiftData

enum PasrStore {
    static let cloudContainer = "iCloud.nl.lrvdlinden.pasr"
    static let appGroup = "group.nl.lrvdlinden.pasr"

    /// The shared store: SwiftData mirrored to the user's private iCloud database.
    /// Falls back to a local-only store if CloudKit cannot be set up, so the app always opens.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([Card.self])
        do {
            #if os(watchOS)
            let config = ModelConfiguration("Pasr", schema: schema, isStoredInMemoryOnly: inMemory,
                                            cloudKitDatabase: inMemory ? .none : .private(cloudContainer))
            #else
            let config = ModelConfiguration("Pasr", schema: schema, isStoredInMemoryOnly: inMemory,
                                            groupContainer: .identifier(appGroup),
                                            cloudKitDatabase: inMemory ? .none : .private(cloudContainer))
            #endif
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            print("Pasr: CloudKit store unavailable, using local store: \(error)")
            let local = ModelConfiguration("PasrLocal", schema: schema, cloudKitDatabase: .none)
            return try! ModelContainer(for: schema, configurations: local)
        }
    }

    /// Permanently removes cards that have been in Recently Deleted for more than 30 days.
    @MainActor
    static func purgeOldDeletions(in context: ModelContext) {
        let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
        let descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.deletedAt != nil })
        guard let deleted = try? context.fetch(descriptor) else { return }
        for card in deleted where (card.deletedAt ?? .now) < cutoff {
            context.delete(card)
        }
        try? context.save()
    }

    @MainActor
    static func insertSamples(into context: ModelContext) {
        let samples: [(String, String, BarcodeFormat, String, CardKind)] = [
            ("Albert Heijn", "2620123456782", .ean13, "#00A0E2", .loyalty),
            ("HEMA", "8712345678906", .ean13, "#E30613", .loyalty),
            ("Bol cadeaukaart", "6064 0012 3456 7890", .code128, "#0000A4", .voucher),
            ("IKEA Family", "6275980123456789", .code128, "#0058A3", .loyalty),
        ]
        for (name, number, format, color, kind) in samples {
            let card = Card(storeName: name, number: number, format: format, kind: kind, colorHex: color)
            card.templateID = StoreTemplates.all.first { name.lowercased().hasPrefix($0.name.lowercased().prefix(4)) }?.id
            if kind == .voucher {
                card.balance = 25
                card.currencyCode = "EUR"
                card.expiresAt = Calendar.current.date(byAdding: .day, value: 40, to: .now)
            }
            context.insert(card)
        }
    }
}
