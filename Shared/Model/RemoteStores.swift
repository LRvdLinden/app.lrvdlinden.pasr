import Foundation

/// Winkels die na de release zijn toegevoegd (in het beheer): de app haalt ze op via de catalogus en bewaart ze in de
/// App Group, met hun logo. Zo komt een nieuwe winkel erbij zonder app-update.
enum RemoteStores {
    struct Stored: Codable, Hashable {
        var id: String
        var name: String
        var domain: String
        var category: String
        var cardHex: String
        var format: String
        var kind: String
        var aliases: [String]
        /// Eerdere kaartkleuren uit het beheer: een kaart in zo'n kleur krijgt de nieuwe kleur mee.
        var previousHex: [String]?
    }

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PasrStore.appGroup)?
            .appending(path: "Stores", directoryHint: .isDirectory)
    }
    private static var listURL: URL? { folder?.appending(path: "stores.json") }
    private static var removedURL: URL? { folder?.appending(path: "removed.json") }

    nonisolated(unsafe) private static var cache: [Stored]?
    nonisolated(unsafe) private static var removedCache: Set<String>?
    nonisolated(unsafe) private static var domainCache: Set<String>?

    /// Winkels die het beheer heeft weggehaald, ook als ze in de app zitten: die staan niet meer in de lijst.
    /// Bestaande kaarten van zo'n winkel blijven gewoon werken.
    static func removedIDs() -> Set<String> {
        if let removedCache { return removedCache }
        let set = removedURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
        removedCache = set
        return set
    }

    static func saveRemoved(_ ids: Set<String>) {
        guard let folder, let url = removedURL else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(ids) { try? data.write(to: url, options: .atomic) }
        removedCache = ids
    }

    /// Het beheer levert voor dit domein een kant-en-klaar logo (en kaartkleur): dan geen stijl uit de app erop.
    static func managesLogo(for domain: String) -> Bool {
        if domainCache == nil { domainCache = Set(load().map(\.domain).filter { d in logoURL(for: d).map { FileManager.default.fileExists(atPath: $0.path) } ?? false }) }
        return domainCache?.contains(domain) ?? false
    }

    /// Was dit een eerdere kaartkleur van deze winkel in het beheer?
    static func isPastColour(_ hex: String, for id: String) -> Bool {
        load().first { $0.id.lowercased() == id.lowercased() }?.previousHex?.contains { $0.caseInsensitiveCompare(hex) == .orderedSame } ?? false
    }

    static func load() -> [Stored] {
        if let cache { return cache }
        guard let url = listURL, let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Stored].self, from: data) else { cache = []; return [] }
        cache = list
        return list
    }

    static func save(_ list: [Stored]) {
        guard let folder, let url = listURL else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(list) { try? data.write(to: url, options: .atomic) }
        cache = list
        domainCache = nil
    }

    static func logoURL(for domain: String) -> URL? {
        guard !domain.isEmpty else { return nil }
        return folder?.appending(path: "logo-\(domain).img")
    }

    static func logo(for domain: String) -> Data? {
        logoURL(for: domain).flatMap { try? Data(contentsOf: $0) }
    }

    /// Als StoreTemplate. Het beheer is leidend: een winkel die ook in de app zit (zelfde id) neemt naam, kleur,
    /// logo en soort uit het beheer over.
    static var templates: [StoreTemplate] {
        load().map { s in
            var t = StoreTemplate(id: s.id, name: s.name, domain: s.domain, category: s.category, colorHex: s.cardHex,
                                  format: BarcodeFormat(rawValue: s.format) ?? .code128, aliases: s.aliases,
                                  kind: CardKind(rawValue: s.kind) ?? .loyalty)
            t.managed = true
            return t
        }
    }
}

/// Saldo-pagina's per winkel-id, uit het beheer (via de catalogus). Ook voor winkels die in de app zitten.
enum BalancePages {
    private static let key = "pasr.balancePages"

    static func save(_ pages: [String: String]) {
        UserDefaults(suiteName: PasrStore.appGroup)?.set(pages, forKey: key)
    }

    static func url(for templateID: String?) -> String? {
        guard let templateID else { return nil }
        return (UserDefaults(suiteName: PasrStore.appGroup)?.dictionary(forKey: key) as? [String: String])?[templateID]
    }
}

extension Card {
    /// Waar je het tegoed kunt nakijken: je eigen adres bij de kaart, anders dat van de winkel uit het beheer.
    var balancePage: URL? {
        let raw = (balanceURL?.isEmpty == false ? balanceURL : nil) ?? BalancePages.url(for: templateID)
        guard let raw, let url = URL(string: raw.hasPrefix("http") ? raw : "https://" + raw), url.scheme == "https" else { return nil }
        return url
    }
}
