import SwiftUI

/// Shown over the app while it is locked with Face ID.
struct LockView: View {
    var onUnlock: () -> Void
    @State private var trying = false

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
                .buttonStyle(.glassProminent)
                .tint(Brand.iris)
                .disabled(trying)
                .padding(.bottom, 40)
            }
        }
        .task { await unlock() }
    }

    @MainActor
    private func unlock() async {
        guard !trying else { return }
        trying = true
        defer { trying = false }
        if await Biometrics.authenticate(reason: String(localized: "Ontgrendel Pasr om je kaarten te zien.")) {
            onUnlock()
        }
    }
}
