import SwiftUI

/// Over de app zolang hij vergrendeld is met Face ID (zelfde gedrag als Pasr).
struct LockView: View {
    var onUnlock: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var trying = false
    /// Het Face ID-venster maakt de app even inactief; vraag niet meteen opnieuw na Annuleer.
    @State private var lastTry = Date.distantPast

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 26) {
                Spacer()
                ZakelijkLogo(size: 34)
                Image(systemName: Biometrics.symbolName)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Pasr Zakelijk is vergrendeld")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await unlock() }
                } label: {
                    Label(String(format: String(localized: "Ontgrendel met %@"), Biometrics.methodName), systemImage: Biometrics.symbolName)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(Theme.accent)
                .disabled(trying)
                .padding(.bottom, 40)
            }
        }
        // Meteen om Face ID vragen als het slot verschijnt, en elke keer dat de app weer vooraan komt.
        .task {
            if scenePhase == .active { await unlock() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, Date.now.timeIntervalSince(lastTry) > 2 { Task { await unlock() } }
        }
    }

    @MainActor
    private func unlock() async {
        guard !trying else { return }
        trying = true
        defer { trying = false; lastTry = .now }
        if await Biometrics.authenticate(reason: String(localized: "Ontgrendel Pasr Zakelijk om stempels te zetten.")) {
            onUnlock()
        }
    }
}

/// Dekt de app af in de appkiezer als de vergrendeling aan staat.
struct PrivacyCover: View {
    var body: some View {
        Theme.bg.ignoresSafeArea().overlay { ZakelijkLogo(size: 30) }
    }
}
