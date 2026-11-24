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
    @FocusState private var typing: Bool

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
            .sheet(item: Binding(get: { result.map { IdentifiedResult(result: $0) } }, set: { if $0 == nil { result = nil } })) { item in
                ScanResultSheet(business: business, initial: item.result)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .trackModal()
            }
        }
        // pas om de camera vragen als splash en slot weg zijn
        .task(id: ModalTracker.shared.locked) {
            guard !ModalTracker.shared.locked else { return }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
            cameraDenied = [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .video))
        }
        // niet rustig (geen beoordelingsvraag) zolang er een klant geholpen wordt: code typen, zoeken of resultaat open
        .onChange(of: result != nil || busy || typing, initial: true) { _, active in ModalTracker.shared.scanning = active }
        .onDisappear { ModalTracker.shared.scanning = false }
        .onChange(of: scenePhase) { _, phase in if phase != .active && torch { torch = false; Torch.set(false) } }
        .onDisappear { if torch { torch = false; Torch.set(false) } }
    }

    @ViewBuilder private var camera: some View {
        if QRScanner.isAvailable && !cameraDenied {
            ZStack {
                QRScanner(paused: result != nil || couponCode != nil || busy || typing || ModalTracker.shared.locked) { code in
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
        Text("Richt de camera op de QR-code van je klant")
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

    private func lookManual() async {
        let normalized = manual.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.range(of: "^PC[A-HJ-NP-Z2-9]{22}$", options: .regularExpression) != nil {
            await look(normalized)
            return
        }
        guard let code = MemberCode.extract(manual) else {
            withAnimation { error = String(localized: "Een code begint met PZ. Typ hem over zoals hij onder de QR-code staat.") }
            errorTick += 1
            return
        }
        typing = false
        await look(code)
    }

    private func look(_ code: String) async {
        let normalized = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.range(of: "^PC[A-HJ-NP-Z2-9]{22}$", options: .regularExpression) != nil {
            couponCode = normalized
            manual = ""
            return
        }
        guard !busy, result == nil else { return }
        busy = true
        defer { busy = false }
        do {
            let r = try await BusinessAPI.scan(code)
            withAnimation { error = nil }
            manual = ""
            result = r
        } catch {
            withAnimation { self.error = error.localizedDescription }
            errorTick += 1
        }
    }
}

private struct IdentifiedResult: Identifiable {
    let result: ScanResult
    var id: String { result.code }
}
