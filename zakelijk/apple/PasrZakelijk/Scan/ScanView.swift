import SwiftUI
import AVFoundation

/// Hoofdscherm: camera die de QR-code van de klant leest, of de code typen. Daarna het resultaat met de knoppen.
struct ScanView: View {
    let business: Business
    @Environment(\.scenePhase) private var scenePhase
    @State private var manual = ""
    @State private var busy = false
    @State private var error: String?
    @State private var result: ScanResult?
    @State private var couponCode: String?
    @State private var torch = false
    @State private var cameraDenied = false
    @State private var errorTick = 0
    @State private var ticketScan: TicketScan?
    @State private var memberScan: MemberScan?
    /// Scannen voor één event (leeg = alle events van de zaak).
    @State private var eventFilter = ""
    @State private var events: [TicketEvent] = []
    @State private var savingUnits: [String: String] = [:]
    @FocusState private var typing: Bool

    private var eventFilterKey: String { "pasr.scan.event." + business.id }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                camera
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(alignment: .bottom) { hint }
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line))
                manualEntry
                if let error {
                    Label { Text(error) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.coral)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BusinessPicker()
                if !events.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { eventMenu }
                }
                if Torch.isAvailable && QRScanner.isAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            torch.toggle()
                            Torch.set(torch)
                        } label: {
                            Image(systemName: torch ? "flashlight.on.fill" : "flashlight.off.fill")
                        }
                        .accessibilityLabel(Text(torch ? "Zaklamp uit" : "Zaklamp aan"))
                    }
                }
            }
            .sensoryFeedback(.error, trigger: errorTick)
            .sheet(isPresented: Binding(get: { couponCode != nil }, set: { if !$0 { couponCode = nil } })) {
                BusinessCouponsView(business: business, initialCode: couponCode ?? "")
                    .trackModal()
            }
            .sheet(item: Binding(get: { ticketScan.map { IdentifiedTicket(scan: $0) } }, set: { if $0 == nil { ticketScan = nil } })) { item in
                TicketScanSheet(scan: item.scan)
                    .presentationDetents([.large])
                    .trackModal()
            }
            .sheet(item: Binding(get: { memberScan.map { IdentifiedMember(scan: $0) } }, set: { if $0 == nil { memberScan = nil } })) { item in
                MemberScanSheet(business: business, scan: item.scan, unit: item.scan.cardID.flatMap { savingUnits[$0] })
                    .presentationDetents([.large])
                    .trackModal()
            }
            .sheet(item: Binding(get: { result.map { IdentifiedResult(result: $0) } }, set: { if $0 == nil { result = nil } })) { item in
                ScanResultSheet(business: business, initial: item.result)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .trackModal()
            }
        }
        .task(id: business.id) { await loadTK() }
        // pas om de camera vragen als splash en slot weg zijn
        .task(id: ModalTracker.shared.locked) {
            guard !ModalTracker.shared.locked else { return }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
            cameraDenied = [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
        }
        // niet rustig (geen beoordelingsvraag) zolang er een klant geholpen wordt: code typen, zoeken of resultaat open
        .onChange(of: result != nil || ticketScan != nil || memberScan != nil || busy || typing, initial: true) { _, active in ModalTracker.shared.scanning = active }
        .onDisappear { ModalTracker.shared.scanning = false }
        .onChange(of: scenePhase) { _, phase in if phase != .active && torch { torch = false; Torch.set(false) } }
        .onDisappear { if torch { torch = false; Torch.set(false) } }
    }

    @ViewBuilder private var camera: some View {
        if QRScanner.isAvailable && !cameraDenied {
            ZStack {
                QRScanner(paused: result != nil || ticketScan != nil || memberScan != nil || couponCode != nil || busy || typing || ModalTracker.shared.locked) { code in
                    Task { await look(code) }
                }
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, dash: [26, 14]))
                    .frame(width: 230, height: 230)
                    .shadow(radius: 8)
                    .accessibilityHidden(true)
                if busy { ProgressView().controlSize(.large).tint(.white) }
            }
            .background(.black)
        } else {
            ContentUnavailableView {
                Label("Camera niet beschikbaar", systemImage: "camera.metering.unknown")
            } description: {
                Text(cameraDenied
                     ? "Geef Pasr Zakelijk toegang tot de camera in Instellingen, of typ de code van de klant hieronder."
                     : "Dit apparaat kan hier geen QR-codes scannen. Typ de code van de klant hieronder.")
            } actions: {
                if cameraDenied, let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Instellingen", destination: url)
                }
            }
            .background(Theme.card)
        }
    }

    private var hint: some View {
        Text(eventTitle.map { String(format: String(localized: "Scannen · %@"), $0) }
             ?? String(localized: "Richt de camera op de QR-code, het ticket of de klantenkaart"))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(.bottom, 14)
            .opacity(QRScanner.isAvailable && !cameraDenied ? 1 : 0)
    }

    private var manualEntry: some View {
        HStack(spacing: 10) {
            TextField("Of typ de code (PZ…)", text: $manual)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .focused($typing)
                .submitLabel(.search)
                .onSubmit { Task { await lookManual() } }
                .fieldStyle()
            Button {
                Task { await lookManual() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
                    .frame(width: 50, height: 50)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }
            .disabled(manual.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            .accessibilityLabel(Text("Zoek code"))
        }
    }

    private var eventTitle: String? {
        guard !eventFilter.isEmpty else { return nil }
        return events.first { $0.id == eventFilter }?.name
    }

    private var eventMenu: some View {
        Menu {
            Picker("Scannen voor", selection: Binding(get: { eventFilter }, set: {
                eventFilter = $0
                UserDefaults.standard.set($0, forKey: eventFilterKey)
            })) {
                Text("Alle events").tag("")
                ForEach(events) { e in
                    Text(verbatim: e.name + " · " + e.startsAt.formatted(.dateTime.day().month(.abbreviated))).tag(e.id)
                }
            }
        } label: {
            Image(systemName: eventFilter.isEmpty ? "ticket" : "ticket.fill")
        }
        .accessibilityLabel(Text("Scannen voor één event"))
    }

    /// Komende events (voor het eventfilter) en de spaar-eenheid per klantenkaart. Mislukt het: geen filter.
    private func loadTK() async {
        eventFilter = UserDefaults.standard.string(forKey: eventFilterKey) ?? ""
        let list = (try? await TKAPI.events(business: business.id)) ?? []
        events = list.filter { $0.isPublished && $0.endsAt > Date.now.addingTimeInterval(-6 * 3600) }
        if !eventFilter.isEmpty && !events.contains(where: { $0.id == eventFilter }) { eventFilter = "" }
        let cards = (try? await TKAPI.memberCards(business: business.id)) ?? []
        savingUnits = Dictionary(cards.map { ($0.id, $0.goals.savingUnit) }, uniquingKeysWith: { a, _ in a })
    }

    private func lookManual() async {
        guard ScanCode.classify(manual) != nil else {
            withAnimation { error = String(localized: "Een code begint met PZ. Typ hem over zoals hij onder de QR-code staat.") }
            errorTick += 1
            return
        }
        typing = false
        await look(manual)
    }

    private func look(_ raw: String) async {
        guard let kind = ScanCode.classify(raw) else {
            withAnimation { error = String(localized: "Deze code is niet bekend. Laat de klant de kaart opnieuw tonen of typ de code over.") }
            errorTick += 1
            return
        }
        if case .coupon(let code) = kind {
            couponCode = code
            manual = ""
            return
        }
        guard !busy, result == nil, ticketScan == nil, memberScan == nil else { return }
        busy = true
        defer { busy = false }
        do {
            switch kind {
            case .stampCard(let code):
                result = try await BusinessAPI.scan(code)
            case .ticket(let code):
                let t: TicketScan
                do {
                    t = try await TKAPI.scanTicket(business: business.id, code: code, event: eventFilter.isEmpty ? nil : eventFilter)
                } catch {
                    if let r = await legacy(code) { result = r; break }
                    throw error
                }
                if t.result == "invalid", let r = await legacy(code) { result = r } else { ticketScan = t }
            case .memberCard(let code):
                let m: MemberScan
                do {
                    m = try await TKAPI.scanMemberCard(business: business.id, code: code)
                } catch {
                    if let r = await legacy(code) { result = r; break }
                    throw error
                }
                if m.result == "invalid", let r = await legacy(code) { result = r } else { memberScan = m }
            case .coupon:
                break
            }
            withAnimation { error = nil }
            manual = ""
        } catch {
            withAnimation { self.error = error.localizedDescription }
            errorTick += 1
        }
    }

    /// Oudere klantcodes zonder PZ: toch nog als stempelkaart proberen.
    private func legacy(_ code: String) async -> ScanResult? {
        guard let c = MemberCode.extract(code) else { return nil }
        return try? await BusinessAPI.scan(c)
    }
}

private struct IdentifiedTicket: Identifiable {
    let scan: TicketScan
    var id: String { scan.code + scan.result }
}

private struct IdentifiedMember: Identifiable {
    let scan: MemberScan
    var id: String { scan.code }
}

private struct IdentifiedResult: Identifiable {
    let result: ScanResult
    var id: String { result.code }
}
