import SwiftUI

/// Uitkomst van een ticketscan aan de deur: groot groen (geldig) of rood met de reden.
struct TicketScanSheet: View {
    let scan: TicketScan
    @Environment(\.dismiss) private var dismiss

    private var color: Color { scan.isValid ? Color(hex: "#12A77E") : Color(hex: "#D93A2B") }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: scan.isValid ? "checkmark" : "xmark")
                .font(.system(size: 30, weight: .heavy))
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.22), in: Circle())
            Text(scan.isValid ? "Geldig" : "Niet geldig")
                .font(.system(size: 40, weight: .heavy))
            if let reason { Text(verbatim: reason).font(.title3.weight(.bold)) }
            if !scan.name.isEmpty || !scan.ticketType.isEmpty {
                Text(verbatim: [scan.name, scan.ticketType].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.title3.weight(.semibold))
            }
            if !scan.eventName.isEmpty {
                Label { Text(verbatim: scan.eventName) } icon: { Image(systemName: "ticket") }
                    .font(.subheadline.weight(.semibold)).opacity(0.9)
            }
            if let inside = scan.checkedIn {
                let total = scan.registered ?? scan.capacity ?? 0
                Text(String(format: String(localized: "%lld / %lld binnen"), inside, total))
                    .font(.headline).monospacedDigit()
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: { Text(scan.isValid ? "Volgende scannen" : "Opnieuw scannen") }
                .buttonStyle(BigButtonStyle(color: .white.opacity(0.25)))
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.ignoresSafeArea())
        .sensoryFeedback(scan.isValid ? .success : .error, trigger: scan.code)
        .accessibilityElement(children: .combine)
    }

    private var reason: String? {
        switch scan.result {
        case "valid": return String(localized: "Toegang")
        case "used":
            if let at = scan.checkedInAt {
                return String(format: String(localized: "Al gebruikt om %@"), at.formatted(date: .omitted, time: .shortened))
            }
            return String(localized: "Al gebruikt")
        case "other_event":
            return scan.eventName.isEmpty ? String(localized: "Ticket voor een ander event")
                : String(format: String(localized: "Ticket voor een ander event: %@"), scan.eventName)
        case "cancelled": return String(localized: "Geannuleerd")
        default: return String(localized: "Ongeldig ticket")
        }
    }
}

/// Uitkomst van een klantenkaartscan aan de kassa: de korting die nu geldt, de spaarstand en de knoppen.
struct MemberScanSheet: View {
    let business: Business
    @State var scan: MemberScan
    /// Spaar-eenheid van de kaart ("visits"/"points"), als bekend.
    var unit: String?
    @Environment(\.dismiss) private var dismiss
    @State private var points = 1
    @State private var busy = false
    @State private var error: String?
    @State private var done: String?
    @State private var tick = 0

    private var discount: Bool { scan.discountNow != nil }
    private var background: Color { discount ? Theme.iris : Color(light: 0x2A2C38, dark: 0x1C1F29) }
    private var usesPoints: Bool { (scan.saving?.unit ?? unit) == "points" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if scan.isValid { validContent } else { invalidContent }
                if let error {
                    Label { Text(error) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .font(.subheadline.weight(.semibold))
                }
                if let done {
                    Label { Text(verbatim: done) } icon: { Image(systemName: "checkmark.circle.fill") }
                        .font(.subheadline.weight(.semibold))
                }
                Button("Klaar") { dismiss() }
                    .buttonStyle(BigButtonStyle(color: .white.opacity(0.18)))
            }
            .padding(24)
        }
        .foregroundStyle(.white)
        .background((scan.isValid ? background : Color(hex: "#D93A2B")).ignoresSafeArea())
        .sensoryFeedback(.success, trigger: tick)
    }

    @ViewBuilder private var validContent: some View {
        Image(systemName: discount ? "percent" : "person.text.rectangle")
            .font(.system(size: 26, weight: .heavy))
            .frame(width: 58, height: 58)
            .background(.white.opacity(0.2), in: Circle())
        if let d = scan.discountNow {
            Text(String(format: String(localized: "%@%% korting"), TKFormat.percent(d.percent)))
                .font(.system(size: 40, weight: .heavy))
            let detail = [d.label, d.until.map { String(format: String(localized: "geldt tot %@"), TKFormat.soon($0)) } ?? ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            if !detail.isEmpty { Text(verbatim: detail).font(.subheadline).opacity(0.9) }
        } else {
            Text("Geen korting vandaag").font(.system(size: 34, weight: .heavy))
            if let n = scan.nextDiscount {
                let when = n.startsAt.map(TKFormat.soon) ?? ""
                let text = [when, n.label, TKFormat.percent(n.percent) + "%"].filter { !$0.isEmpty }.joined(separator: " · ")
                Text(String(format: String(localized: "Volgende: %@"), text)).font(.subheadline).opacity(0.9)
            }
        }
        Text(verbatim: memberLine).font(.headline)
        if let saving = scan.saving { savingControls(saving) }
    }

    private var memberLine: String {
        var parts: [String] = []
        if let name = scan.memberName, !name.isEmpty { parts.append(name) }
        parts.append(scan.cardName.isEmpty ? String(localized: "Lid") : scan.cardName)
        parts.append(scan.number)
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func savingControls(_ saving: SavingInfo) -> some View {
        HStack(spacing: 10) {
            Text("Spaarstand").font(.subheadline.weight(.bold))
            ProgressView(value: Double(min(saving.count, saving.target)), total: Double(saving.target)).tint(.white)
            Text(verbatim: "\(saving.count)/\(saving.target)").font(.subheadline.weight(.bold)).monospacedDigit()
        }
        .padding(12)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        if !saving.reward.isEmpty {
            Text(String(format: String(localized: "Beloning: %@"), saving.reward)).font(.subheadline).opacity(0.9)
        }
        if usesPoints {
            Stepper(value: $points, in: 1...1000) {
                Text(String(format: String(localized: "%lld punten"), points)).monospacedDigit()
            }
        }
        Button {
            Task { await visit() }
        } label: {
            Label(usesPoints ? "Punten registreren" : "Bezoek registreren", systemImage: "checkmark")
        }
        .buttonStyle(BigButtonStyle(color: .white, foreground: Theme.iris))
        .disabled(busy)
        if saving.canRedeem {
            Button { Task { await redeem() } } label: { Label("Beloning inwisselen", systemImage: "gift.fill") }
                .buttonStyle(BigButtonStyle(color: .white.opacity(0.25)))
                .disabled(busy)
        }
    }

    @ViewBuilder private var invalidContent: some View {
        Image(systemName: "xmark")
            .font(.system(size: 26, weight: .heavy))
            .frame(width: 58, height: 58)
            .background(.white.opacity(0.2), in: Circle())
        Text("Niet geldig").font(.system(size: 36, weight: .heavy))
        Text(scan.result == "other_business" ? "Deze kaart hoort bij een andere zaak." : "Deze klantenkaart is niet bekend.")
            .font(.headline)
    }

    private func visit() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if let s = try await TKAPI.visit(business: business.id, code: scan.code, points: usesPoints ? points : nil) {
                scan.saving = SavingInfo(merging: s, unit: scan.saving?.unit)
            }
            done = usesPoints ? String(format: String(localized: "%lld punten geregistreerd"), points) : String(localized: "Bezoek geregistreerd")
            tick += 1
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func redeem() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            if let s = try await TKAPI.redeem(business: business.id, code: scan.code) {
                scan.saving = SavingInfo(merging: s, unit: scan.saving?.unit)
            }
            done = String(localized: "Beloning ingewisseld")
            tick += 1
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension SavingInfo {
    init(merging s: SavingInfo, unit: String?) {
        self = s
        if self.unit == nil { self.unit = unit }
    }
}
