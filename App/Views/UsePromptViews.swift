import SwiftUI
import SwiftData

/// Wanneer een kaart als "gebruikt" telt (sinds build 47). Even openen en kijken telt niet meer: Pasr kan de kassascan
/// niet zien. Een moment komt er alleen bij als
/// 1. de barcode minstens 5 seconden in beeld was en je bij het sluiten "Ja" zegt op "Gebruikt bij PLUS?";
/// 2. met "Alleen bij de winkel" (standaard aan, met locatietoegang) vraagt Pasr dat alleen als je bij een filiaal bent;
///    weet Pasr dat je elders bent, dan vraagt en bewaart het niets; zonder locatie vraagt het gewoon;
/// 3. of een aankoop binnenkomt via Opdrachten (Apple Pay, zie PurchaseCapture).
enum UseCapture {
    static let askKey = "pasr.uses.ask"
    static let onlyAtStoreKey = "pasr.uses.onlyAtStore"
    /// Zo lang moet de barcode in beeld zijn geweest.
    static let minimumVisible: TimeInterval = 5
    /// Zo lang staat de vraag onderin; geen reactie = niet tellen.
    static let promptDuration: TimeInterval = 8

    static var asks: Bool { UserDefaults.standard.object(forKey: askKey) as? Bool ?? true }
    static var onlyAtStore: Bool { UserDefaults.standard.object(forKey: onlyAtStoreKey) as? Bool ?? true }

    /// Bij deze soorten heeft de vraag zin (een ticket gebruik je één keer).
    static func applies(to card: Card) -> Bool { card.kind != .ticket && !card.isShareExpired }

    /// Wat er bij het sluiten moet gebeuren: niets, of vragen (met de filiaalnaam als Pasr die lokaal kent).
    @MainActor
    static func decide(for card: Card, visible: TimeInterval) async -> (ask: Bool, place: String?) {
        guard asks, applies(to: card), visible >= minimumVisible else { return (false, nil) }
        guard onlyAtStore else { return (true, await NearbyStores.shared.placeName(for: card)) }
        switch await NearbyStores.shared.storeCheck(for: card) {
        case .atStore(let name): return (true, name)
        case .elsewhere: return (false, nil)
        case .unknown: return (true, nil)
        }
    }
}

/// De vraag die even onderin verschijnt na het sluiten van een kaart: "Gebruikt bij PLUS? Ja · Nee".
struct UsePrompt: Identifiable, Equatable {
    let id = UUID()
    let cardID: UUID
    let title: String
    let place: String?
}

struct UsePromptBar: View {
    let prompt: UsePrompt
    let card: Card?
    var onYes: () -> Void
    var onNo: () -> Void
    @State private var progress: Double = 1

    var body: some View {
        HStack(spacing: 12) {
            if let card { UseLogoTile(card: card) }
            VStack(alignment: .leading, spacing: 1) {
                Text("Gebruikt bij \(prompt.title)?")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                Text("Alleen Ja telt mee in Laatst gebruikt")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Nee", action: onNo)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            Button("Ja", action: onYes)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Brand.iris)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottom) {
            // hoe lang de vraag nog blijft staan
            GeometryReader { geo in
                Capsule().fill(Brand.iris.opacity(0.5))
                    .frame(width: geo.size.width * progress, height: 3)
            }
            .frame(height: 3)
            .padding(.horizontal, 18)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .onAppear {
            withAnimation(.linear(duration: UseCapture.promptDuration)) { progress = 0 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Gebruikt bij \(prompt.title)?"))
        .accessibilityAction(named: Text("Ja")) { onYes() }
        .accessibilityAction(named: Text("Nee")) { onNo() }
    }
}

/// Instellingen › Gebruik bijhouden.
struct UseSettingsSection: View {
    @AppStorage(UseCapture.askKey) private var ask = true
    @AppStorage(UseCapture.onlyAtStoreKey) private var onlyAtStore = true
    private var nearby = NearbyStores.shared

    var body: some View {
        Section {
            Toggle(isOn: $ask) {
                SettingsLabel("Vraag na het tonen", symbol: "questionmark.bubble.fill", color: Brand.iris)
            }
            if ask {
                Toggle(isOn: $onlyAtStore) {
                    SettingsLabel("Alleen bij de winkel", symbol: "location.fill", color: .blue)
                }
                .onChange(of: onlyAtStore) { _, on in
                    if on, !nearby.hasLocation { Task { _ = await nearby.locationForPin() } }
                }
            }
            NavigationLink { PurchaseAutomationView() } label: {
                SettingsLabel("Aankopen vanzelf vastleggen", symbol: "wave.3.right.circle.fill", color: Brand.mint)
            }
            NavigationLink { ReceiptsView(embedded: true) } label: {
                SettingsLabel("Bonnetjes", symbol: "doc.text.fill", color: .orange)
            }
        } header: {
            Text("Laatst gebruikt")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var text = String(localized: "Even kijken telt niet. Was de barcode minstens 5 seconden in beeld, dan vraagt Pasr bij het sluiten of je de kaart gebruikte; alleen Ja komt in Laatst gebruikt.")
        if ask && onlyAtStore {
            text += " " + (nearby.hasLocation
                ? String(localized: "Met Alleen bij de winkel vraagt Pasr het niet als je niet bij een filiaal bent. Dat kijkt Pasr op je iPhone na met de winkels die het al kent; je locatie gaat nergens heen.")
                : String(localized: "Zonder locatietoegang vraagt Pasr het altijd."))
        }
        return text
    }
}
