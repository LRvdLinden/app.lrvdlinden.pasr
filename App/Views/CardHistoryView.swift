import SwiftUI
import SwiftData
#if canImport(SafariServices)
import SafariServices
#endif

/// Tekst voor een regel uit de geschiedenis (ook voor de achterkant van de Wallet-pas).
enum CardHistoryFormat {
    static func money(_ value: Double, _ code: String?) -> String {
        value.formatted(.currency(code: code ?? "EUR").locale(Locale(identifier: "nl_NL")))
    }

    static func title(_ e: CardEvent, card: Card) -> String {
        switch e.kind {
        case .shown: return e.place ?? String(localized: "Getoond")
        case .spent: return e.place ?? String(localized: "Uitgegeven")
        case .topup: return String(localized: "Opgewaardeerd")
        case .set: return String(localized: "Tegoed aangepast")
        }
    }

    static func amount(_ e: CardEvent, card: Card) -> String? {
        switch e.kind {
        case .spent: return e.amount.map { "−" + money($0, card.currencyCode) }
        case .topup: return e.amount.map { "+" + money($0, card.currencyCode) }
        case .set: return e.balance.map { money($0, card.currencyCode) }
        case .shown: return nil
        }
    }

    /// "8 nov · −€ 11,07 · PLUS Apeldoorn"
    static func line(_ e: CardEvent, card: Card) -> String {
        let day = e.date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "nl_NL")))
        var parts = [day]
        if let a = amount(e, card: card) { parts.append(a) }
        switch e.kind {
        case .shown: parts.append(e.place ?? String(localized: "getoond"))
        case .spent: if let p = e.place { parts.append(p) }
        case .topup: parts.append(String(localized: "opgewaardeerd"))
        case .set: parts.append(String(localized: "tegoed aangepast"))
        }
        return parts.joined(separator: " · ")
    }

    static func symbol(_ e: CardEvent) -> (String, Color) {
        switch e.kind {
        case .shown: ("barcode.viewfinder", Brand.iris)
        case .spent: ("cart.fill", Brand.coral)
        case .topup: ("plus.circle.fill", Brand.mint)
        case .set: ("pencil.circle.fill", .gray)
        }
    }
}

/// Geschiedenis van een kaart, zoals "Laatste transacties" in Apple Wallet: wanneer je hem liet zien (en waar), en bij
/// een voucher het tegoed met uitgaven en opwaarderingen. Pasr ziet niet of een kaart echt is gescand.
struct CardHistorySheet: View {
    @Bindable var card: Card
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var entry: SpendSheet.Mode?
    @State private var checking: URL?

    private var isVoucher: Bool { card.kind == .voucher }
    private var events: [CardEvent] { card.history }
    private var recent: [CardEvent] { events.filter { $0.date > .now.addingTimeInterval(-30 * 86_400) } }
    private var older: [CardEvent] { events.filter { $0.date <= .now.addingTimeInterval(-30 * 86_400) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        if isVoucher {
                            Text("Tegoed").font(.subheadline).foregroundStyle(.secondary)
                            Text(CardHistoryFormat.money(card.balance ?? 0, card.currencyCode))
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .contentTransition(.numericText())
                        }
                        if let last = card.lastShown {
                            Text("Laatst gebruikt \(last.date.formatted(.relative(presentation: .named)))\(last.place.map { " · \($0)" } ?? "")")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if let used = card.lastUsed {
                            Text("Laatst gebruikt \(used.formatted(.relative(presentation: .named)))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))

                    if isVoucher {
                        Button { entry = .spent } label: { Label("Uitgegeven…", systemImage: "cart") }
                        Button { entry = .topup } label: { Label("Opgewaardeerd…", systemImage: "plus.circle") }
                        Button { entry = .set } label: { Label("Tegoed aanpassen…", systemImage: "pencil") }
                        if let page = card.balancePage {
                            Button { checkBalance(page) } label: {
                                Label("Saldo checken bij \(page.host() ?? "de uitgever")", systemImage: "safari")
                            }
                        }
                    }
                }

                Section {
                    if recent.isEmpty {
                        Text(isVoucher ? "Nog geen uitgaven deze maand." : "Deze maand nog niet gebruikt.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(recent) { row($0) }
                        .onDelete { remove(recent, $0) }
                } header: {
                    Text("Laatste 30 dagen")
                }
                if !older.isEmpty {
                    Section("Eerder") {
                        ForEach(older) { row($0) }
                            .onDelete { remove(older, $0) }
                    }
                }
                Section {
                } footer: {
                    Text(isVoucher
                         ? "Pasr vraagt na het tonen hoeveel je uitgaf; de winkel of uitgever geeft het tegoed niet aan Pasr door. Veeg een regel weg om hem ongedaan te maken. Staat de kaart in Apple Wallet, dan werkt Pasr de pas daar ook bij."
                         : "Pasr houdt bij wanneer je de kaart liet zien, en bij welk filiaal als je locatie aanstaat. Of hij echt is gescand, weet Pasr niet. Dit blijft op je iPhone.")
                }
            }
            .navigationTitle(card.storeName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } } }
            .sheet(item: $entry) { mode in
                SpendSheet(card: card, mode: mode)
                    .presentationDetents([.medium])
            }
            #if canImport(SafariServices)
            .sheet(item: Binding(get: { checking.map(IdentifiedURL.init) }, set: { checking = $0?.url })) { item in
                SafariView(url: item.url).ignoresSafeArea()
                    .onDisappear {
                        Task { try? await Task.sleep(for: .milliseconds(450)); entry = .set }
                    }
            }
            #endif
        }
    }

    private func row(_ e: CardEvent) -> some View {
        let (symbol, color) = CardHistoryFormat.symbol(e)
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(CardHistoryFormat.title(e, card: card)).font(.body.weight(.semibold))
                Text(e.date.formatted(.relative(presentation: .named)))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let amount = CardHistoryFormat.amount(e, card: card) {
                    Text(amount).font(.body.monospacedDigit())
                        .foregroundStyle(e.kind == .topup ? Brand.mint : .primary)
                }
                if e.kind != .set, let b = e.balance {
                    Text("tegoed \(CardHistoryFormat.money(b, card.currencyCode))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func remove(_ list: [CardEvent], _ offsets: IndexSet) {
        for i in offsets { card.removeEvent(list[i]) }
        try? context.save()
        Task { await WalletPass.refreshIfInWallet(card) }
    }

    private func checkBalance(_ url: URL) {
        CardClipboard.copy(card.number)
        checking = url
    }
}

/// Uitgegeven, opgewaardeerd of tegoed aanpassen. Na het tonen van een voucher vraagt Pasr dit vanzelf.
struct SpendSheet: View {
    enum Mode: String, Identifiable { case spent, topup, set; var id: String { rawValue } }
    @Bindable var card: Card
    let mode: Mode
    var place: String? = nil
    /// Na het tonen: met "Niet meer vragen".
    var asked = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SpendSheet.askKey) private var ask = true
    @State private var text = ""
    @FocusState private var focused: Bool

    static let askKey = "pasr.voucher.askSpent"

    private var value: Double? { Double(text.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }) }
    private var balance: Double { card.balance ?? 0 }

    private var title: String {
        switch mode {
        case .spent: String(localized: "Hoeveel heb je uitgegeven?")
        case .topup: String(localized: "Hoeveel is erbij gekomen?")
        case .set: String(localized: "Wat is het tegoed nu?")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Tegoed \(CardHistoryFormat.money(balance, card.currencyCode))")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(mode == .spent ? "−" : (mode == .topup ? "+" : "")).font(.system(size: 40, weight: .heavy, design: .rounded))
                    TextField("0,00", text: $text)
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .fixedSize()
                    Text(card.currencyCode ?? "EUR").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                }
                if mode == .spent {
                    HStack(spacing: 10) {
                        Button("Niets") { dismiss() }.buttonStyle(.bordered)
                        if balance > 0 {
                            Button("Alles (\(CardHistoryFormat.money(balance, card.currencyCode)))") { save(balance) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                if let place, mode == .spent {
                    Label(place, systemImage: "mappin.and.ellipse").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if asked {
                    Button("Niet meer vragen na het tonen") { ask = false; dismiss() }
                        .font(.footnote)
                }
            }
            .padding()
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") { if let value { save(value) } }.disabled(value == nil)
                }
            }
            .onAppear {
                if mode == .set { text = balance.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "nl_NL"))) }
                focused = true
            }
        }
    }

    private func save(_ amount: Double) {
        switch mode {
        case .spent: if amount > 0 { card.recordSpent(amount, place: place) }
        case .topup: if amount > 0 { card.recordTopUp(amount) }
        case .set: card.recordBalance(amount)
        }
        try? context.save()
        let card = card
        Task { await WalletPass.refreshIfInWallet(card) }
        dismiss()
    }
}

/// Kaartnummer klaarzetten om te plakken op de saldo-pagina (alleen op dit apparaat, 2 minuten).
enum CardClipboard {
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]],
                                      options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)])
        #endif
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

#if canImport(SafariServices)
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Brand.iris)
        vc.dismissButtonStyle = .done
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
#endif
