import Foundation
import SwiftData
import SwiftUI
import AppIntents
import UserNotifications

/// Aankopen vanzelf vastleggen (sinds build 47): de App Intent "Aankoop vastleggen" krijgt van Opdrachten de winkel en
/// het bedrag van een Apple Pay-betaling (persoonlijke automatisering "Transactie"). Pasr zoekt de kaart die het best
/// bij die winkel past (naam, aliassen en website uit de catalogus) en zet een gebruiksmoment met het bedrag in
/// Laatst gebruikt. Bij een cadeaukaart gaat het bedrag pas van het tegoed af als je dat in de melding bevestigt.
///
/// Privacy: alles gebeurt op de iPhone. Pasr gebruikt geen locatie en bewaart de winkelnaam uit de betaling niet; die
/// gaat ook niet naar de server. Alleen de bestaande accountsync van het moment (winkel van de kaart, tijd, bedrag).
enum PurchaseCapture {
    static let notificationCategory = "pasr.pay.voucher"
    static let bookAction = "pasr.pay.book"
    static let skipAction = "pasr.pay.skip"

    struct Outcome {
        let message: String
        let cardID: UUID?
    }

    /// Verwerkt één aankoop. Zonder passende kaart wordt niets bewaard (wel een melding als dat mag).
    @MainActor
    static func record(merchant: String, amountText: String?, in context: ModelContext, date: Date = .now) -> Outcome {
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = amountText.flatMap(parseAmount)
        let cards = (try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        guard !name.isEmpty, let card = PurchaseMatcher.best(merchant: name, among: cards) else {
            let text = String(localized: "Geen kaart gevonden voor \(name.isEmpty ? String(localized: "deze aankoop") : name)")
            notify(title: text, body: String(localized: "Er is niets bewaard. Voeg de kaart toe in Pasr als je er een hebt."), id: "pay-none")
            return Outcome(message: text, cardID: nil)
        }
        let useID = card.recordUse(place: nil, source: "pay", date: date)
        let use = card.history.first { $0.id == useID }
        var message = String(localized: "Vastgelegd bij \(card.storeName)")
        if let amount, amount > 0, use?.amount == nil {
            let money = CardHistoryFormat.money(amount, card.currencyCode)
            if card.kind == .voucher {
                // cadeaukaart: eerst vragen voordat het van het tegoed gaat
                card.updateUse(useID) { $0.pendingAmount = amount }
                message = String(localized: "\(money) bij \(card.storeName): afboeken van je tegoed?")
                notify(title: String(localized: "\(money) afboeken van \(card.storeName)?"),
                       body: String(localized: "Tegoed nu \(CardHistoryFormat.money(card.balance ?? 0, card.currencyCode)). Houd de melding ingedrukt om af te boeken."),
                       id: "pay-\(useID.uuidString)", category: notificationCategory,
                       info: ["cardID": card.id.uuidString, "useID": useID.uuidString])
            } else {
                card.setAmount(amount, forUse: useID)
                message = String(localized: "\(money) bij \(card.storeName) vastgelegd")
            }
        }
        try? context.save()
        return Outcome(message: message, cardID: card.id)
    }

    /// Bevestigd in de melding: het wachtende bedrag gaat van het tegoed af.
    @MainActor
    static func book(cardID: UUID, useID: UUID, in context: ModelContext) {
        guard let card = try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.id == cardID })).first,
              let pending = card.history.first(where: { $0.id == useID })?.pendingAmount else { return }
        card.setAmount(pending, forUse: useID)
        try? context.save()
        Task { await WalletPass.refreshIfInWallet(card) }
    }

    /// Niet afboeken: het moment blijft, zonder bedrag.
    @MainActor
    static func skip(cardID: UUID, useID: UUID, in context: ModelContext) {
        guard let card = try? context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.id == cardID })).first else { return }
        card.updateUse(useID) { $0.pendingAmount = nil }
        try? context.save()
    }

    /// "€ 1.234,56", "12,34 €", "EUR 12.34", "-6,48" of "6.48" → 1234.56 / 12.34 / 6.48.
    static func parseAmount(_ text: String) -> Double? {
        var t = text.filter { $0.isNumber || $0 == "," || $0 == "." }
        guard !t.isEmpty else { return nil }
        if let comma = t.lastIndex(of: ","), let dot = t.lastIndex(of: ".") {
            // beide: het laatste teken is het decimaalteken
            if comma > dot { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else { t = t.replacingOccurrences(of: ",", with: "") }
        } else if t.contains(",") {
            let parts = t.split(separator: ",")
            t = parts.count == 2 && parts[1].count == 3 && !text.contains("€") ? t.replacingOccurrences(of: ",", with: "")
                : t.replacingOccurrences(of: ",", with: ".")
        } else if t.filter({ $0 == "." }).count > 1 {
            t = t.replacingOccurrences(of: ".", with: "")
        }
        guard let v = Double(t), v.isFinite, v >= 0, v < 1_000_000 else { return nil }
        return (v * 100).rounded() / 100
    }

    /// Meldingen alleen als je ze eerder hebt toegestaan (Pasr vraagt het hier niet).
    static func notify(title: String, body: String, id: String, category: String? = nil, info: [String: String] = [:]) {
        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional || status == .ephemeral else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.threadIdentifier = "purchases"
            if let category { content.categoryIdentifier = category }
            content.userInfo = info
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    /// Knoppen onder de melding "€ 12,34 afboeken van …?".
    static func registerCategories() {
        let book = UNNotificationAction(identifier: bookAction, title: String(localized: "Afboeken"), options: [.authenticationRequired])
        let skip = UNNotificationAction(identifier: skipAction, title: String(localized: "Niet afboeken"), options: [])
        let category = UNNotificationCategory(identifier: notificationCategory, actions: [book, skip], intentIdentifiers: [])
        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            center.setNotificationCategories(existing.filter { $0.identifier != notificationCategory }.union([category]))
        }
    }
}

/// Zoekt de kaart die het best past bij de winkelnaam van een betaling ("ALBERT HEIJN 1234 APELDOORN", "Jumbo
/// Twello", "BOL.COM", "AH to go"). Kijkt naar de naam op de kaart, de winkelnaam en aliassen in de catalogus en de
/// website ("ah.nl" → "ah"). Korte namen (AH, DA) tellen alleen als eerste woord.
enum PurchaseMatcher {
    static func fold(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "nl_NL"))
            .replacingOccurrences(of: "&", with: " and ").replacingOccurrences(of: "'", with: "")
        let mapped = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func terms(for card: Card) -> [String] {
        var list = [card.storeName]
        if let t = StoreTemplates.template(id: card.templateID) {
            list.append(t.name)
            list += t.aliases
            list.append(stem(t.domain))
        }
        if let w = card.website { list.append(stem(w)) }
        return Array(Set(list.map(fold).filter { $0.count >= 2 }))
    }

    /// "ah.nl" → "ah", "c-and-a.com" → "c and a", "www.basic-fit.com" → "basic fit".
    static func stem(_ domain: String) -> String {
        var d = domain.lowercased()
        for p in ["https://", "http://", "www."] where d.hasPrefix(p) { d.removeFirst(p.count) }
        d = String(d.split(separator: "/").first ?? "")
        let parts = d.split(separator: ".")
        return fold((parts.count > 1 ? parts.dropLast() : parts[...]).joined(separator: " "))
    }

    /// Hoe goed een naam past (hoger is beter), of nil.
    static func score(merchant: String, term: String) -> Int? {
        let m = fold(merchant).split(separator: " ").map(String.init)
        let t = term.split(separator: " ").map(String.init)
        guard !m.isEmpty, !t.isEmpty else { return nil }
        let joinedTerm = t.joined()
        // hele woorden achter elkaar
        if t.count <= m.count {
            for start in 0...(m.count - t.count) where Array(m[start..<(start + t.count)]) == t {
                if joinedTerm.count < 3 && start != 0 { continue }   // "ah", "da": alleen vooraan
                return joinedTerm.count * 10 + (start == 0 ? 5 : 0)
            }
        }
        // aan elkaar geschreven ("BOLCOM", "BASICFIT"): alleen bij langere namen
        if joinedTerm.count >= 5, m.joined().contains(joinedTerm) { return joinedTerm.count * 8 }
        return nil
    }

    static func best(merchant: String, among cards: [Card]) -> Card? {
        let candidates = cards.filter { $0.deletedAt == nil && !$0.isTemporary && $0.kind != .ticket }
        var best: (score: Int, card: Card)?
        for card in candidates {
            guard let s = terms(for: card).compactMap({ score(merchant: merchant, term: $0) }).max() else { continue }
            if let b = best {
                if s > b.score || (s == b.score && Card.score(card) > Card.score(b.card)) { best = (s, card) }
            } else {
                best = (s, card)
            }
        }
        return best?.card
    }
}

// MARK: - Opdrachten

/// "Aankoop vastleggen": voor de persoonlijke automatisering Transactie (Apple Pay) in de app Opdrachten.
struct RecordPurchaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Aankoop vastleggen"
    static let description = IntentDescription(
        "Zet een aankoop in Laatst gebruikt van de kaart die bij de winkel past. Koppel deze actie in Opdrachten aan de automatisering Transactie: Opdrachten geeft de verkoper en het bedrag door. Alles blijft op dit apparaat.",
        categoryName: "Laatst gebruikt")
    static let openAppWhenRun = false

    @Parameter(title: "Winkel", description: "De verkoper uit de betaling (Opdrachten: Verkoper).")
    var merchant: String

    @Parameter(title: "Bedrag", description: "Het bedrag (Opdrachten: Bedrag), als getal of tekst.")
    var amount: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Leg aankoop bij \(\.$merchant) van \(\.$amount) vast")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = PurchaseCapture.record(merchant: merchant, amountText: amount, in: PasrStore.app.mainContext)
        return .result(dialog: IntentDialog(stringLiteral: outcome.message))
    }
}

struct PasrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordPurchaseIntent(),
                    phrases: ["Leg een aankoop vast in \(.applicationName)",
                              "Aankoop vastleggen in \(.applicationName)",
                              "Record a purchase in \(.applicationName)"],
                    shortTitle: "Aankoop vastleggen",
                    systemImageName: "wave.3.right.circle")
        AppShortcut(intent: ShowReceiptIntent(),
                    phrases: ["Toon bonnetje in \(.applicationName)",
                              "Zoek een bon in \(.applicationName)",
                              "Show receipt in \(.applicationName)"],
                    shortTitle: "Toon bonnetje",
                    systemImageName: "doc.text")
    }
}

// MARK: - Uitleg in Instellingen

struct PurchaseAutomationView: View {
    @Environment(\.openURL) private var openURL
    @State private var notificationsAllowed: Bool?

    private let steps: [(String, String)] = [
        ("plus.circle.fill", String(localized: "Open Opdrachten, kies Automatisering en tik op + (Nieuwe automatisering).")),
        ("wave.3.right.circle.fill", String(localized: "Kies Transactie. Selecteer je betaalkaarten in Wallet, laat Wanneer op Ik tik staan en kies Voer onmiddellijk uit.")),
        ("square.stack.3d.up.fill", String(localized: "Kies Nieuwe lege automatisering en voeg de actie Aankoop vastleggen van Pasr toe.")),
        ("text.cursor", String(localized: "Tik op Winkel en kies Verkoper. Tik op Bedrag en kies Bedrag.")),
        ("checkmark.circle.fill", String(localized: "Klaar. Betaal je met Apple Pay bij een winkel waarvan je een kaart in Pasr hebt, dan staat de aankoop in Laatst gebruikt.")),
    ]

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "wave.3.right.circle.fill")
                        .font(.system(size: 44)).foregroundStyle(Brand.mint)
                    Text("Aankopen vanzelf vastleggen").font(.title2.weight(.bold))
                    Text("Betaal je met Apple Pay, dan geeft de app Opdrachten de winkel en het bedrag aan Pasr. Pasr zoekt de kaart die erbij past en zet de aankoop in Laatst gebruikt. Bij een cadeaukaart vraagt Pasr eerst in een melding of het bedrag van je tegoed af mag.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            Section("Zo stel je het in") {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(.subheadline.weight(.heavy)).foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Brand.iris, in: Circle())
                            .accessibilityHidden(true)
                        Text(step.1).font(.subheadline)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Stap \(i + 1): \(step.1)"))
                }
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Open Opdrachten", systemImage: "arrow.up.forward.app.fill")
                        .font(.body.weight(.semibold))
                }
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            Section {
                if notificationsAllowed == false {
                    Button {
                        Task { notificationsAllowed = await Reminders.requestPermission() }
                    } label: {
                        Label("Meldingen toestaan", systemImage: "bell.badge.fill")
                    }
                }
            } header: {
                Text("Meldingen")
            } footer: {
                Text("Met meldingen laat Pasr weten als er geen kaart bij een winkel past, en vraagt het bij een cadeaukaart of het bedrag afgeboekt mag worden.")
            }
            Section {
            } footer: {
                Text("Alles gebeurt op je iPhone. Pasr gebruikt hiervoor geen locatie en bewaart de winkelnaam uit de betaling niet. Past er geen kaart, dan wordt er niets bewaard. Heb je een Pasr-account, dan gaat alleen het moment mee (winkel van de kaart, tijd en bedrag), net als een bedrag dat je zelf invult.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Brand.ink.ignoresSafeArea())
        .navigationTitle("Vanzelf vastleggen")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            notificationsAllowed = status == .authorized || status == .provisional
        }
    }
}
