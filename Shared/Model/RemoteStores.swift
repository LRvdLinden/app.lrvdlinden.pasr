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
    }

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PasrStore.appGroup)?
            .appending(path: "Stores", directoryHint: .isDirectory)
    }
    private static var listURL: URL? { folder?.appending(path: "stores.json") }

    nonisolated(unsafe) private static var cache: [Stored]?

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
    }

    static func logoURL(for domain: String) -> URL? {
        guard !domain.isEmpty else { return nil }
        return folder?.appending(path: "logo-\(domain).img")
    }

    static func logo(for domain: String) -> Data? {
        logoURL(for: domain).flatMap { try? Data(contentsOf: $0) }
    }

    /// Als StoreTemplate; een winkel die ook in de app zit (zelfde id) wordt niet dubbel getoond.
    static var templates: [StoreTemplate] {
        load().map { s in
            StoreTemplate(id: s.id, name: s.name, domain: s.domain, category: s.category, colorHex: s.cardHex,
                          format: BarcodeFormat(rawValue: s.format) ?? .code128, aliases: s.aliases,
                          kind: CardKind(rawValue: s.kind) ?? .loyalty)
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
