import Foundation
import SwiftData

/// Store logos. Known stores have their logo in the app (Shared/StoreLogos, filled by
/// tools/fetch_logos.py), so it shows at once, offline too. For other websites the device fetches
/// the icon the store publishes (apple-touch-icon or site icon). Users can switch logos off in Settings.
enum LogoService {
    static let settingKey = "fetchStoreLogos"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }

    /// Adds website logos to cards that have no logo yet.
    @MainActor
    static func fillMissing(in context: ModelContext) async {
        guard isEnabled else { return }
        let all = (try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        var changed = false
        // Cards with a store logo get the clean logo that ships with the app, and, if their colour was
        // never changed, the brand colour that goes with it.
        for card in all where card.logoData == nil || card.logoFromWebsite {
            guard let domain = card.logoDomain, let bundled = bundledLogo(for: domain) else { continue }
            if card.logoData != bundled {
                card.logoData = bundled
                card.logoFromWebsite = true
                changed = true
            }
            if let template = StoreTemplates.template(id: card.templateID), card.colorHex == template.colorHex,
               template.cardHex != template.colorHex {
                card.colorHex = template.cardHex
                changed = true
            }
        }
        for card in all where card.logoData == nil {
            guard let domain = card.logoDomain, let logo = await logo(for: domain) else { continue }
            guard card.logoData == nil else { continue } // the user picked one meanwhile
            card.logoData = logo
            card.logoFromWebsite = true
            changed = true
        }
        if changed { try? context.save() }
    }

    /// Removes logos that came from websites (when the setting is switched off). Own logos stay.
    @MainActor
    static func removeWebsiteLogos(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        for card in all where card.logoFromWebsite {
            card.logoData = nil
            card.logoFromWebsite = false
        }
        try? context.save()
    }

    // MARK: Fetching

    @MainActor private static var cache: [String: Data] = [:]
    @MainActor private static var inFlight: [String: Task<Data?, Never>] = [:]
    private static let failuresKey = "logoFailures"

    /// Logos are kept on disk for 30 days, so the store list and cards show them straight away.
    private static var cacheFolder: URL {
        let folder = URL.cachesDirectory.appending(path: "StoreLogos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func diskURL(_ domain: String) -> URL { cacheFolder.appending(path: domain + ".png") }

    /// The logo that ships with the app for a known store, e.g. "ah.nl".
    static func bundledLogo(for domain: String) -> Data? {
        guard !domain.isEmpty,
              let url = Bundle.main.url(forResource: domain, withExtension: "png")
                ?? Bundle.main.url(forResource: domain, withExtension: "png", subdirectory: "StoreLogos")
        else { return nil }
        return try? Data(contentsOf: url)
    }

    /// A logo that is in the app or already cached, without going to the network.
    @MainActor
    static func cachedLogo(for domain: String) -> Data? {
        if let cached = cache[domain] { return cached }
        if let bundled = bundledLogo(for: domain) {
            cache[domain] = bundled
            return bundled
        }
        let url = diskURL(domain)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              Date.now.timeIntervalSince(modified) < 30 * 86_400,
              let data = try? Data(contentsOf: url) else { return nil }
        cache[domain] = data
        return data
    }

    /// PNG logo of at most 256 px for a domain such as "ah.nl", or nil.
    @MainActor
    static func logo(for domain: String, force: Bool = false) async -> Data? {
        if !force, let cached = cachedLogo(for: domain) { return cached }
        if let running = inFlight[domain] { return await running.value }
        var failures = UserDefaults.standard.dictionary(forKey: failuresKey) as? [String: Double] ?? [:]
        if !force, let failed = failures[domain], Date.now.timeIntervalSince1970 - failed < 7 * 86_400 { return nil }

        let task = Task.detached(priority: .utility) { await download(domain: domain) }
        inFlight[domain] = task
        let found = await task.value
        inFlight[domain] = nil
        failures = UserDefaults.standard.dictionary(forKey: failuresKey) as? [String: Double] ?? [:]
        if let found {
            cache[domain] = found
            try? found.write(to: diskURL(domain), options: .atomic)
            failures[domain] = nil
        } else {
            failures[domain] = Date.now.timeIntervalSince1970
        }
        UserDefaults.standard.set(failures, forKey: failuresKey)
        return found
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
            "Accept-Language": "nl-NL,nl;q=0.9",
        ]
        return URLSession(configuration: config)
    }()

    private static func download(domain: String) async -> Data? {
        var candidates: [URL] = []
        // 1. Icons the home page declares, best first.
        for host in ["https://www.\(domain)/", "https://\(domain)/"] {
            guard let url = URL(string: host),
                  case let (data, response)? = try? await session.data(from: url),
                  let html = String(data: data.prefix(600_000), encoding: .utf8) ?? String(data: data.prefix(600_000), encoding: .isoLatin1)
            else { continue }
            candidates += iconLinks(in: html, base: response.url ?? url)
            break
        }
        // 2. The usual fixed places.
        candidates += ["https://www.\(domain)/apple-touch-icon.png", "https://\(domain)/apple-touch-icon.png",
                       "https://www.\(domain)/favicon.ico"].compactMap(URL.init(string:))

        var seen = Set<URL>()
        for url in candidates where seen.insert(url).inserted {
            guard case let (data, response)? = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
                  data.count < 3_000_000,
                  let image = ImageTools.cgImage(from: data, maxSide: 512),
                  min(image.width, image.height) >= 48
            else { continue }
            return ImageTools.png(image, maxSide: 256)
        }
        return nil
    }

    /// `<link rel="apple-touch-icon" …>` and `<link rel="icon" sizes="…">` from a page, largest first.
    static func iconLinks(in html: String, base: URL) -> [URL] {
        guard let tagPattern = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]),
              let attrPattern = try? NSRegularExpression(
                pattern: "([a-zA-Z-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))") else { return [] }
        let ns = html as NSString
        var found: [(URL, Int)] = []
        for match in tagPattern.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            var attrs: [String: String] = [:]
            let tns = tag as NSString
            for a in attrPattern.matches(in: tag, range: NSRange(location: 0, length: tns.length)) {
                let key = tns.substring(with: a.range(at: 1)).lowercased()
                let value = (2...4).compactMap { i -> String? in
                    let r = a.range(at: i)
                    return r.location == NSNotFound ? nil : tns.substring(with: r)
                }.first ?? ""
                attrs[key] = value
            }
            let rel = attrs["rel"]?.lowercased() ?? ""
            guard rel.contains("icon"), !rel.contains("mask"), let href = attrs["href"], !href.hasSuffix(".svg"),
                  let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL
            else { continue }
            let declared = attrs["sizes"]?.split(separator: "x").first.flatMap { Int($0) } ?? 0
            let score = (rel.contains("apple-touch-icon") ? 10_000 : 0) + declared
            found.append((url, score))
        }
        return found.sorted { $0.1 > $1.1 }.map(\.0)
    }
}
