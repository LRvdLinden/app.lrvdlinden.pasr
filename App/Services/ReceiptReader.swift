import Foundation
import Vision
import CoreSpotlight
import UniformTypeIdentifiers
import UserNotifications
import AppIntents
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Leest het totaalbedrag en de datum van een kassabon, op het toestel met Vision (geen server). Je controleert ze
/// altijd zelf voordat de bon wordt bewaard.
enum ReceiptReader {
    struct Result: Equatable {
        var total: Double?
        var date: Date?
        var text: [String] = []
    }

    #if canImport(UIKit)
    static func read(_ images: [UIImage]) async -> Result {
        var lines: [String] = []
        for image in images.prefix(Receipt.maxPages) {
            lines += await recognize(image)
        }
        return parse(lines)
    }

    private static func recognize(_ image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                // van boven naar beneden; Vision rekent y van onder
                let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                continuation.resume(returning: Self.joinRows(sorted))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["nl-NL", "en-US"]
            request.usesLanguageCorrection = false
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request]) }
                catch { continuation.resume(returning: []) }
            }
        }
    }

    /// Tekst die op dezelfde hoogte staat ("TOTAAL" links, "23,45" rechts) wordt één regel.
    private static func joinRows(_ observations: [VNRecognizedTextObservation]) -> [String] {
        var rows: [(y: CGFloat, h: CGFloat, parts: [(x: CGFloat, text: String)])] = []
        for o in observations {
            guard let text = o.topCandidates(1).first?.string else { continue }
            let box = o.boundingBox
            if let i = rows.firstIndex(where: { abs($0.y - box.midY) < max($0.h, box.height) * 0.6 }) {
                rows[i].parts.append((box.minX, text))
            } else {
                rows.append((box.midY, box.height, [(box.minX, text)]))
            }
        }
        return rows.map { $0.parts.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
    }
    #endif

    // MARK: Uit de tekst halen (los te testen)

    private static let amountPattern = try! NSRegularExpression(
        pattern: #"(?<![\d,.])(\d{1,3}(?:[.\s]\d{3})*|\d+)[,.](\d{2})(?![\d])"#)
    private static let totalWords = ["te betalen", "totaal", "total", "tot.", "eindtotaal", "betaald", "bedrag", "pin", "amount", "to pay"]
    private static let weakWords = ["subtotaal", "subtotal", "btw", "vat", "korting", "wisselgeld", "retour", "statiegeld", "excl"]

    static func amounts(in line: String) -> [Double] {
        let ns = line as NSString
        return amountPattern.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let whole = ns.substring(with: m.range(at: 1)).filter(\.isNumber)
            let cents = ns.substring(with: m.range(at: 2))
            guard let v = Double("\(whole).\(cents)"), v > 0, v < 100_000 else { return nil }
            return v
        }
    }

    static func parse(_ lines: [String], now: Date = .now) -> Result {
        var result = Result(text: lines)
        let lower = lines.map { $0.lowercased() }
        // 1. regels met "totaal" of "te betalen" (niet subtotaal of btw): het bedrag op die regel of de volgende
        var candidates: [Double] = []
        for (i, line) in lower.enumerated() {
            guard totalWords.contains(where: { line.contains($0) }), !weakWords.contains(where: { line.contains($0) }) else { continue }
            let here = amounts(in: lines[i])
            if let v = here.last { candidates.append(v) }
            else if i + 1 < lines.count, let v = amounts(in: lines[i + 1]).last { candidates.append(v) }
        }
        // het grootste totaal (een pinbon noemt het bedrag soms nog een keer, kleinere zijn deelbedragen)
        result.total = candidates.max() ?? lines.flatMap(amounts).max()
        result.date = date(in: lines, now: now)
        return result
    }

    private static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mrt": 3, "maa": 3, "mar": 3, "apr": 4, "mei": 5, "may": 5, "jun": 6, "jul": 7, "aug": 8,
        "sep": 9, "okt": 10, "oct": 10, "nov": 11, "dec": 12,
    ]

    /// Eerste geldige datum: "12-11-2026", "12/11/26", "12.11.2026", "2026-11-12" of "12 nov 2026"; niet in de toekomst
    /// en niet ouder dan 10 jaar.
    static func date(in lines: [String], now: Date = .now) -> Date? {
        let cal = Calendar(identifier: .gregorian)
        let patterns: [(String, (NSTextCheckingResult, NSString) -> DateComponents?)] = [
            (#"(?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)"#, { m, s in
                DateComponents(year: Int(s.substring(with: m.range(at: 1))), month: Int(s.substring(with: m.range(at: 2))),
                               day: Int(s.substring(with: m.range(at: 3))))
            }),
            (#"(?<!\d)(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})(?!\d)"#, { m, s in
                var y = Int(s.substring(with: m.range(at: 3))) ?? 0
                if y < 100 { y += 2000 }
                return DateComponents(year: y, month: Int(s.substring(with: m.range(at: 2))), day: Int(s.substring(with: m.range(at: 1))))
            }),
            (#"(?i)(?<!\d)(\d{1,2})\s*([a-z]{3})[a-z]*\.?\s*(\d{2,4})(?!\d)"#, { m, s in
                guard let month = months[s.substring(with: m.range(at: 2)).lowercased()] else { return nil }
                var y = Int(s.substring(with: m.range(at: 3))) ?? 0
                if y < 100 { y += 2000 }
                return DateComponents(year: y, month: month, day: Int(s.substring(with: m.range(at: 1))))
            }),
        ]
        let earliest = cal.date(byAdding: .year, value: -10, to: now) ?? .distantPast
        let latest = now.addingTimeInterval(86_400)
        for line in lines {
            let ns = line as NSString
            for (pattern, make) in patterns {
                guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
                for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    guard var comps = make(m, ns), let month = comps.month, (1...12).contains(month),
                          let day = comps.day, (1...31).contains(day) else { continue }
                    comps.hour = 12
                    if let d = cal.date(from: comps), cal.component(.day, from: d) == day, d >= earliest, d <= latest { return d }
                }
            }
        }
        return nil
    }
}

/// Herinnering een maand voordat de garantie afloopt (lokale melding, 10:00).
enum ReceiptReminders {
    static func id(_ r: Receipt) -> String { "receipt-\(r.id.uuidString)" }

    @MainActor
    static func schedule(_ r: Receipt) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id(r)])
        guard let until = r.warrantyUntil,
              let month = Calendar.current.date(byAdding: .month, value: -1, to: Calendar.current.startOfDay(for: until)),
              let fire = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: month), fire > .now else { return }
        if await center.notificationSettings().authorizationStatus == .notDetermined { await Reminders.requestPermission() }
        let content = UNMutableNotificationContent()
        let what = r.title.isEmpty ? r.storeName : "\(r.title) (\(r.storeName))"
        content.title = String(localized: "Garantie loopt over een maand af")
        content.body = String(localized: "De garantie op \(what) loopt tot \(until.formatted(.dateTime.day().month(.wide).year().locale(UseFormat.locale))). Je bon staat in Pasr.")
        content.sound = .default
        content.threadIdentifier = "receipts"
        content.userInfo = ["receiptID": r.id.uuidString]
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id(r), content: content, trigger: trigger))
    }

    static func cancel(_ r: Receipt) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(r)])
    }
}

/// Bonnetjes in Spotlight ("PLUS bon"), alleen in de index op dit toestel; zonder de foto zelf.
enum ReceiptSpotlight {
    static let domain = "nl.lrvdlinden.pasr.receipts"

    static func index(_ receipts: [Receipt]) {
        let items = receipts.map { r -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .content)
            let day = r.date.formatted(.dateTime.day().month(.wide).year().locale(UseFormat.locale))
            attrs.title = r.title.isEmpty ? String(localized: "\(r.storeName) bon") : "\(r.storeName) bon · \(r.title)"
            var desc = [day]
            if let t = r.total { desc.append(CardHistoryFormat.money(t, r.currencyCode)) }
            if let w = r.warrantyUntil {
                desc.append(String(localized: "garantie tot \(w.formatted(.dateTime.day().month(.abbreviated).year().locale(UseFormat.locale)))"))
            }
            attrs.contentDescription = desc.joined(separator: " · ")
            attrs.keywords = [r.storeName, "bon", "bonnetje", "kassabon", "receipt", "garantie", r.title].filter { !$0.isEmpty }
            return CSSearchableItem(uniqueIdentifier: r.id.uuidString, domainIdentifier: domain, attributeSet: attrs)
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            if !items.isEmpty { index.indexSearchableItems(items) }
        }
    }
}

// MARK: - Opdrachten en Siri: "Toon bonnetje"

struct ReceiptEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Bonnetje"
    static let defaultQuery = ReceiptQuery()
    let id: UUID
    let title: String
    let subtitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)", image: .init(systemName: "doc.text"))
    }

    @MainActor init(_ r: Receipt) {
        id = r.id
        title = r.title.isEmpty ? "\(r.storeName) bon" : "\(r.storeName) · \(r.title)"
        var parts = [r.date.formatted(.dateTime.day().month(.wide).year().locale(UseFormat.locale))]
        if let t = r.total { parts.append(CardHistoryFormat.money(t, r.currencyCode)) }
        subtitle = parts.joined(separator: " · ")
    }
}

struct ReceiptQuery: EntityStringQuery {
    @MainActor private func all() -> [Receipt] {
        (try? PasrStore.app.mainContext.fetch(FetchDescriptor<Receipt>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }
    @MainActor func entities(for identifiers: [UUID]) async throws -> [ReceiptEntity] {
        all().filter { identifiers.contains($0.id) }.map(ReceiptEntity.init)
    }
    @MainActor func entities(matching string: String) async throws -> [ReceiptEntity] {
        all().filter { $0.matches(string) }.prefix(30).map(ReceiptEntity.init)
    }
    @MainActor func suggestedEntities() async throws -> [ReceiptEntity] {
        all().prefix(15).map(ReceiptEntity.init)
    }
}

struct ShowReceiptIntent: AppIntent {
    static let title: LocalizedStringResource = "Toon bonnetje"
    static let description = IntentDescription("Opent een bewaard bonnetje in Pasr, bijvoorbeeld voor een garantieclaim.",
                                               categoryName: "Bonnetjes")
    static let openAppWhenRun = true

    @Parameter(title: "Bonnetje")
    var receipt: ReceiptEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationRouter.pendingReceiptID = receipt.id
        return .result()
    }
}
