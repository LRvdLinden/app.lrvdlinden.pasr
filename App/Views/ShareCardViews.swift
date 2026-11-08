import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Share a card: for good (link or QR code) or temporarily, until a date of your choice. A picture of the card
/// (front, without the code) goes along with the link, so in WhatsApp or mail the other person sees what it is.
struct ShareCardSheet: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss

    enum Mode: Hashable { case permanent, temporary }
    enum Period: Hashable, CaseIterable { case hour, day, week, custom }

    @State private var mode: Mode = .temporary
    @State private var period: Period = .day
    @State private var customUntil = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    @State private var busy = false
    @State private var error: String?
    @State private var activity: ActivityItems?
    @State private var sent: [TempShare.Sent] = []
    @State private var lastTemp: TempShare.Sent?
    @State private var editing: TempShare.Sent?

    private var until: Date {
        switch period {
        case .hour: .now.addingTimeInterval(3600)
        case .day: .now.addingTimeInterval(86_400)
        case .week: .now.addingTimeInterval(7 * 86_400)
        case .custom: customUntil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if card.isTemporary {
                    Section {
                        Label("Deze kaart is tijdelijk met je gedeeld en kun je niet verder delen.", systemImage: "clock.badge.xmark")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Picker("Delen", selection: $mode.animation()) {
                            Text("Tijdelijk").tag(Mode.temporary)
                            Text("Blijvend").tag(Mode.permanent)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                    if mode == .temporary { temporarySections } else { permanentSection }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Deel \(card.storeName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Klaar") { dismiss() } }
            }
            .onAppear { sent = TempShare.sent(for: card).filter(\.isActive) }
            .sheet(item: $editing) { item in
                TempShareEditSheet(item: item, card: card) { sent = TempShare.sent(for: card).filter(\.isActive) }
            }
            #if canImport(UIKit)
            .sheet(item: $activity) { items in
                ActivityView(items: items.items).ignoresSafeArea().presentationDetents([.medium, .large])
            }
            #endif
        }
    }

    // MARK: Tijdelijk

    @ViewBuilder private var temporarySections: some View {
        Section {
            CardFaceView(appearance: shareAppearance(until: until, masked: true), showsCode: false)
                .aspectRatio(Brand.cardAspect, contentMode: .fit)
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            Picker("Geldig", selection: $period.animation()) {
                Text("1 uur").tag(Period.hour)
                Text("1 dag").tag(Period.day)
                Text("1 week").tag(Period.week)
                Text("Eigen").tag(Period.custom)
            }
            .pickerStyle(.segmented)
            if period == .custom {
                DatePicker("Tot", selection: $customUntil,
                           in: Date.now.addingTimeInterval(600)...Date.now.addingTimeInterval(Double(TempShare.maxDays) * 86_400))
            }
            Button {
                Task { await shareTemporarily() }
            } label: {
                HStack {
                    Label("Deel tot \(until.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.badge.checkmark")
                    Spacer()
                    if busy { ProgressView() }
                }
            }
            .disabled(busy)
        } header: {
            Text("Tijdelijk delen")
        } footer: {
            Text(error ?? String(localized: "De ander voegt de kaart toe aan Pasr. Na het einde verdwijnt de code en werkt de link niet meer. Tijdelijke kaarten kunnen niet in Apple Wallet en niet verder worden gedeeld."))
                .foregroundStyle(error == nil ? Color.secondary : Brand.coral)
        }

        if let lastTemp {
            Section("Link") {
                BarcodeView(value: lastTemp.url.absoluteString, format: .qr)
                    .padding(14)
                    .frame(width: 200, height: 200)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                Button { presentActivity(for: lastTemp) } label: { Label("Opnieuw versturen", systemImage: "square.and.arrow.up") }
            }
        }

        if !sent.isEmpty {
            Section {
                ForEach(sent) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tot \(item.until.formatted(date: .abbreviated, time: .shortened))")
                            Text(item.until, format: .relative(presentation: .named)).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Wijzig") { editing = item }
                            .buttonStyle(.borderless)
                        Button("Stop", role: .destructive) { Task { await stop(item) } }
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Nu tijdelijk gedeeld")
            } footer: {
                Text("Stop je, dan werkt de kaart bij de ander direct niet meer.")
            }
        }
    }

    private func shareTemporarily() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let item = try await TempShare.create(for: card, until: until)
            lastTemp = item
            sent = TempShare.sent(for: card).filter(\.isActive)
            presentActivity(for: item)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func stop(_ item: TempShare.Sent) async {
        do {
            try await TempShare.stop(item)
            sent = TempShare.sent(for: card).filter(\.isActive)
            if lastTemp?.token == item.token { lastTemp = nil }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func presentActivity(for item: TempShare.Sent) {
        let date = item.until.formatted(date: .abbreviated, time: .shortened)
        let text = String(localized: "Je mag mijn \(card.storeName)-kaart gebruiken tot \(date). Open de link om hem aan Pasr toe te voegen:") + "\n" + item.url.absoluteString
        activity = ActivityItems(items: shareItems(text: text, appearance: shareAppearance(until: item.until, masked: true)))
    }

    // MARK: Blijvend

    @ViewBuilder private var permanentSection: some View {
        if let url = CardShare.url(for: card) {
            Section {
                Text("Laat de ander deze code scannen met de camera van zijn iPhone, of stuur de link.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                BarcodeView(value: url.absoluteString, format: .qr)
                    .padding(18)
                    .frame(width: 230, height: 230)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                Button {
                    let text = String(localized: "Hier is de \(card.storeName)-kaart. Open de link om hem aan Pasr toe te voegen:") + "\n" + url.absoluteString
                    activity = ActivityItems(items: shareItems(text: text, appearance: shareAppearance(until: nil, masked: false)))
                } label: {
                    Label("Stuur link", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Logo's, foto's en notities gaan niet mee. Wie de link heeft, kan de kaart blijvend gebruiken.")
            }
        } else {
            Section { Text("Deze kaart kan niet worden gedeeld.").foregroundStyle(.secondary) }
        }
    }

    // MARK: Afbeelding

    /// Voorkant van de kaart. Bij tijdelijk delen zonder nummer, zodat de afbeelding zelf niet als kaart werkt.
    private func shareAppearance(until: Date?, masked: Bool) -> CardAppearance {
        var a = CardAppearance(card)
        a.isShared = false
        a.tempUntil = until
        a.tempRevoked = false
        if masked { a.isLocked = true }
        return a
    }

    private func shareItems(text: String, appearance: CardAppearance) -> [Any] {
        var items: [Any] = []
        #if canImport(UIKit)
        let renderer = ImageRenderer(content: CardFaceView(appearance: appearance, showsCode: false)
            .frame(width: 360, height: 360 / Brand.cardAspect)
            .padding(20)
            .environment(\.colorScheme, .dark))
        renderer.scale = 3
        renderer.isOpaque = false
        if let image = renderer.uiImage { items.append(image) }
        #endif
        items.append(text)
        return items
    }
}

struct ActivityItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

#if canImport(UIKit)
/// The system share sheet with a picture and text (WhatsApp, Mail, Berichten…).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

/// Shown when someone opens a temporary share link: the card, until when it works, and one button to add it.
struct ReceiveTempCardSheet: View {
    let token: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil && $0.shareToken != nil }) private var temps: [Card]
    @State private var state: Fetch = .loading
    @State private var angle: Double = 0

    enum Fetch {
        case loading, ok([String: Any], Date), expired(Date?), revoked, notFound, failed(String)
    }

    private var alreadyAdded: Bool { temps.contains { $0.shareToken == token } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                switch state {
                case .loading:
                    ProgressView().controlSize(.large)
                case .ok(let fields, let until):
                    let card = preview(fields, until)
                    Text("Iemand deelt tijdelijk een kaart met je.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    FlipCardView(appearance: card, angle: angle)
                        .aspectRatio(Brand.cardAspect, contentMode: .fit)
                        .frame(maxWidth: 380)
                        .padding(.horizontal)
                        .onTapGesture { withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { angle = angle == 0 ? 180 : 0 } }
                    Label {
                        Text("Werkt tot \(until.formatted(date: .complete, time: .shortened))")
                    } icon: { Image(systemName: "clock") }
                        .font(.footnote).foregroundStyle(.secondary)
                    if alreadyAdded {
                        Label("Deze kaart staat al in je Pasr", systemImage: "checkmark.circle.fill").foregroundStyle(Brand.mint)
                    }
                    Button { add(fields, until) } label: {
                        Label("Voeg toe aan Pasr", systemImage: "plus").frame(maxWidth: 260).padding(.vertical, 6)
                    }
                    .pasrGlassButton(prominent: true)
                    .tint(Brand.iris)
                    .disabled(alreadyAdded)
                case .expired(let date):
                    message("clock.badge.xmark", String(localized: "Deze kaart is verlopen"),
                            date.map { String(localized: "De ander deelde hem tot \($0.formatted(date: .abbreviated, time: .shortened)).") }
                                ?? String(localized: "De periode waarin deze kaart werkte is voorbij."))
                case .revoked:
                    message("hand.raised.fill", String(localized: "Delen is gestopt"),
                            String(localized: "De ander heeft het delen van deze kaart gestopt."))
                case .notFound:
                    message("questionmark.circle", String(localized: "Deze link werkt niet"),
                            String(localized: "Vraag de ander om de kaart opnieuw te delen vanuit Pasr."))
                case .failed(let text):
                    message("wifi.exclamationmark", String(localized: "Kaart niet opgehaald"), text)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle("Tijdelijke kaart")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Sluit") { dismiss() } } }
            .task { await load() }
        }
    }

    private func message(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44, weight: .semibold)).foregroundStyle(Brand.gradient)
            Text(title).font(.title2.bold())
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func preview(_ fields: [String: Any], _ until: Date) -> CardAppearance {
        let card = TempShare.makeCard(token: token, fields: fields, until: until)
        return CardAppearance(card)
    }

    private func load() async {
        guard !token.isEmpty else { state = .notFound; return }
        do {
            switch try await TempShare.fetch(token) {
            case .ok(let fields, let until):
                state = .ok(fields, until)
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { angle = 180 }
            case .expired(let date): state = .expired(date)
            case .revoked: state = .revoked
            case .notFound: state = .notFound
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func add(_ fields: [String: Any], _ until: Date) {
        let card = TempShare.makeCard(token: token, fields: fields, until: until)
        context.insert(card)
        try? context.save()
        let context = context
        Task { await LogoService.fillMissing(in: context) }
        dismiss()
    }
}

/// Shown when someone opens a shared card link: a preview and one button to add it.
struct ReceiveCardSheet: View {
    let shared: SharedCard
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]
    @State private var angle: Double = 0

    private var alreadyAdded: Bool { cards.contains { $0.number == shared.c && $0.formatRaw == shared.f } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Iemand heeft een kaart met je gedeeld.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                FlipCardView(appearance: shared.appearance, angle: angle)
                    .aspectRatio(Brand.cardAspect, contentMode: .fit)
                    .frame(maxWidth: 380)
                    .padding(.horizontal)
                    .onTapGesture { withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { angle = angle == 0 ? 180 : 0 } }

                if alreadyAdded {
                    Label("Deze kaart staat al in je Pasr", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Brand.mint)
                }
                Button {
                    add()
                } label: {
                    Label("Voeg toe aan Pasr", systemImage: "plus")
                        .frame(maxWidth: 260)
                        .padding(.vertical, 6)
                }
                .pasrGlassButton(prominent: true)
                .tint(Brand.iris)
                .disabled(alreadyAdded)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Brand.ink.ignoresSafeArea())
            .navigationTitle(shared.n)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { dismiss() } }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { angle = 180 }
            }
        }
    }

    private func add() {
        let card = shared.makeCard()
        card.refreshCodeImage()
        context.insert(card)
        try? context.save()
        let context = context
        Task { await LogoService.fillMissing(in: context) }
        dismiss()
    }
}

/// An incoming shared card, for `.sheet(item:)`.
struct IncomingShare: Identifiable {
    let id = UUID()
    let card: SharedCard
}

/// An incoming temporary share link.
struct IncomingTempShare: Identifiable {
    let id = UUID()
    let token: String
}
