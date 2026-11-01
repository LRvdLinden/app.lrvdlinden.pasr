import SwiftUI

/// Shown over the app while it is locked with Face ID.
struct LockView: View {
    var onUnlock: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var trying = false
    /// The Face ID sheet itself makes the app briefly inactive; don't ask again right after a cancel.
    @State private var lastTry = Date.distantPast

    var body: some View {
        ZStack {
            Brand.ink.ignoresSafeArea()
            VStack(spacing: 26) {
                Spacer()
                Text("pasr")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(Brand.gradient)
                Image(systemName: Biometrics.symbolName)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await unlock() }
                } label: {
                    Label("Ontgrendel met \(Biometrics.methodName)", systemImage: Biometrics.symbolName)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 6)
                }
                .pasrGlassButton(prominent: true)
                .tint(Brand.iris)
                .disabled(trying)
                .padding(.bottom, 40)
            }
        }
        // Ask for Face ID straight away: when the lock appears with the app in front, and every time the app
        // comes back to the front (Face ID can't run while the app is still in the background).
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
        if await Biometrics.authenticate(reason: String(localized: "Ontgrendel Pasr om je kaarten te zien.")) {
            onUnlock()
        }
    }
}
