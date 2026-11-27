import SwiftUI
import SwiftData

// MARK: Klantenkaart met barcode van een zaak: aansluiten (pasr.nl/add/m/<kaart>) en wat er onder de kaart staat
// (korting nu of de volgende, spaarstand, meldingen, verwijderen). Scannen doet de zaak met Pasr Zakelijk.

enum MemberDiscountText {
    /// "Nu 15% korting t/m 15 dec" of "Nu 15% korting · happy hour".
    static func now(_ d: MemberDiscount) -> String {
        var s = String(localized: "Nu \(d.percentText ?? "") korting")
        if let label = d.label { s += " · " + label }
        if let until = d.until { s += " " + String(localized: "t/m \(until.formatted(.dateTime.day().month(.abbreviated)))") }
        return s
    }

    /// "Geen korting vandaag · volgende: di 17:00 · 20% happy hour".
    static func none(next: MemberDiscount?) -> String {
        guard let next else { return String(localized: "Geen korting vandaag") }
        var parts: [String] = []
        if let start = next.startsAt {
            let calendar = Calendar.current
            let sameDay = calendar.isDateInToday(start) || calendar.isDateInTomorrow(start)
            parts.append(sameDay ? start.formatted(.relative(presentation: .named)) + " " + start.formatted(date: .omitted, time: .shortened)
                                 : start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
        }
        if let p = next.percentText { parts.append(p) }
        if let label = next.label { parts.append(label) }
        return String(localized: "Geen korting vandaag · volgende: \(parts.joined(separator: " · "))")
    }
}

/// Venster bij pasr.nl/add/m/<kaart>: de kaart in de stijl van de zaak, "Mijn naam tonen aan <zaak>" en Toevoegen.
struct MemberCardJoinSheet: View {
    let cardID: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]

    @State private var info: BusinessPasses.MemberCardInfo?
    @State private var logo: Data?
    @State private var missing: String?
    @State private var shareName = false
    @State private var busy = false
    @State private var error: String?
    @State private var added: Card?

    private var signedIn: Bool { AccountService.shared.isSignedIn }
    private var existing: Card? { BusinessPasses.memberCard(card: cardID, in: cards) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let missing {
                        ContentUnavailableView(missing, systemImage: "exclamationmark.triangle",
                                               description: Text("Vraag de zaak om een nieuwe link of QR-code."))
                    } else if let info {
                        content(info)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle(added != nil ? Text("Toegevoegd") : Text("Toevoegen aan Pasr?"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(added != nil ? "Klaar" : "Annuleer", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder private func content(_ info: BusinessPasses.MemberCardInfo) -> some View {
        if added != nil {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Brand.mint)
            Text("Toegevoegd").font(.title.bold())
        } else {
            Text("KLANTENKAART").font(.caption.weight(.bold)).foregroundStyle(.secondary)
        }
        CardFaceView(appearance: appearance(info), showsCode: false)
            .aspectRatio(Brand.cardAspect, contentMode: .fit)
            .frame(maxWidth: 380)
        if let summary = info.summary {
            Text(summary).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        if let now = info.discountNow {
            Label(MemberDiscountText.now(now), systemImage: "percent").font(.subheadline.weight(.semibold))
        } else if let next = info.nextDiscount {
            Label(MemberDiscountText.none(next: next), systemImage: "calendar").font(.subheadline)
        }
        if let error {
            Text(error).font(.footnote).foregroundStyle(Brand.coral).multilineTextAlignment(.center)
        }
        if let card = added ?? existing {
            if added == nil {
                Label("Deze klantenkaart staat al in je Pasr.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.mint)
            } else {
                Text("Laat de barcode aan de kassa scannen; korting en spaarstand gaan vanzelf mee.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button {
                dismiss()
                NotificationRouter.pendingCardID = card.id
            } label: {
                Label("Bekijk in Pasr", systemImage: "rectangle.portrait.on.rectangle.portrait").frame(maxWidth: 260).padding(.vertical, 6)
            }
            .pasrGlassButton(prominent: true)
            .tint(Brand.iris)
        } else if signedIn {
            Toggle(isOn: $shareName) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mijn naam tonen aan \(info.business ?? info.name)")
                    Text("Uit: de zaak ziet alleen je kaartnummer.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Brand.iris)
            .padding(14)
            .background(Brand.inkRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button { Task { await join() } } label: {
                HStack {
                    if busy { ProgressView() }
                    Label("Toevoegen", systemImage: "plus")
                }
                .frame(maxWidth: 260).padding(.vertical, 6)
            }
            .pasrGlassButton(prominent: true)
            .tint(Brand.iris)
            .disabled(busy)
        } else {
            Text("Log eerst in met je Pasr-account (Instellingen › Account); je kaartnummer hoort bij je account.")
                .font(.footnote).foregroundStyle(Brand.coral).multilineTextAlignment(.center)
        }
    }

    private func appearance(_ info: BusinessPasses.MemberCardInfo) -> CardAppearance {
        if let card = added ?? existing { return CardAppearance(card) }
        return CardAppearance(storeName: info.name, number: "", format: .code128, colorHex: info.color, kind: .loyalty, logoData: logo)
    }

    private func load() async {
        do {
            let result = try await BusinessPasses.memberCard(id: cardID)
            info = result
            logo = await BusinessCards.logoData(result.logo)
        } catch {
            missing = error.localizedDescription
        }
    }

    private func join() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let card = try await BusinessPasses.join(card: cardID, shareName: shareName, in: context)
            withAnimation { added = card }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Onder een klantenkaart van een zaak in de stapel: korting nu (of de volgende), spaarstand, meldingen en verwijderen.
struct MemberCardPanel: View {
    let card: Card
    let width: CGFloat
    var onDelete: () -> Void

    @Environment(\.modelContext) private var context
    @State private var notify = false
    @State private var busy = false
    @State private var error: String?

    private var accent: Color { Color(hex: card.colorHex) }

    var body: some View {
        let d = card.details
        VStack(alignment: .leading, spacing: 12) {
            discountRow(d)
            if let target = d.savingTarget, target > 0 {
                savingRow(count: d.savingCount ?? 0, target: target, reward: d.savingReward, canRedeem: d.savingCanRedeem == true)
            }
            Divider()
            Toggle(isOn: Binding(get: { notify }, set: { new in Task { await setNotify(new) } })) {
                Label("Melding bij nieuwe korting", systemImage: "bell.badge")
            }
            .tint(Brand.iris)
            .disabled(busy)
            if let error {
                Text(error).font(.caption).foregroundStyle(Brand.coral)
            }
            Button(role: .destructive, action: onDelete) {
                Label("Kaart verwijderen", systemImage: "trash")
            }
            .font(.subheadline)
        }
        .padding(14)
        .frame(width: width, alignment: .leading)
        .background(Brand.inkRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { notify = card.details.memberNotify ?? false }
        .task { await BusinessPasses.refreshAll(in: context) }
    }

    @ViewBuilder private func discountRow(_ d: CardDetails) -> some View {
        if let now = d.discountNow {
            Label(MemberDiscountText.now(now), systemImage: "percent")
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if d.nextDiscount != nil {
            Label(MemberDiscountText.none(next: d.nextDiscount), systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func savingRow(count: Int, target: Int, reward: String?, canRedeem: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Spaarstand").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(min(count, target))/\(target)").font(.subheadline.weight(.bold)).monospacedDigit()
            }
            ProgressView(value: Double(min(count, target)), total: Double(target)).tint(accent)
            Text(canRedeem
                 ? String(localized: "Beloning klaar: \(reward ?? String(localized: "je beloning")). Laat je kaart scannen.")
                 : String(localized: "Nog \(max(target - count, 0)) tot \(reward ?? String(localized: "je beloning"))"))
                .font(.caption)
                .foregroundStyle(canRedeem ? Brand.mint : Color.secondary)
        }
    }

    private func setNotify(_ on: Bool) async {
        busy = true
        error = nil
        defer { busy = false }
        let before = notify
        notify = on
        do {
            try await BusinessPasses.setNotify(card, on: on)
            try? context.save()
        } catch {
            notify = before
            self.error = error.localizedDescription
        }
    }
}
