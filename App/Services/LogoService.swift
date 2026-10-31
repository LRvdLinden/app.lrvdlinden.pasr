import Foundation
import SwiftData

/// Fetches a store's logo from its own website: the icon the store publishes for home screens
/// (apple-touch-icon) or, failing that, its site icon. This happens on the device; Pasr ships
/// no logos and runs no server. Users can switch it off in Settings.
enum LogoService {
    static let settingKey = "fetchStoreLogos"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }

    /// Adds website logos to cards that have no logo yet.
    @MainActor
    static func fillMissing(in context: ModelContext) async {
        guard isEnabled else { return }
        let all = (try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        var changed = false
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
    private static let failuresKey = "logoFailures"

    /// PNG logo of at most 256 px for a domain such as "ah.nl", or nil.
    @MainActor
    static func logo(for domain: String, force: Bool = false) async -> Data? {
        if let cached = cache[domain] { return cached }
        var failures = UserDefaults.standard.dictionary(forKey: failuresKey) as? [String: Double] ?? [:]
        if !force, let failed = failures[domain], Date.now.timeIntervalSince1970 - failed < 7 * 86_400 { return nil }

        let found = await Task.detached(priority: .utility) { await download(domain: domain) }.value
        if let found {
            cache[domain] = found
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
