import SwiftUI

/// Vergrendelscherm: vraagt meteen om Face ID / Touch ID; de knop is er voor als je annuleert.
/// Zonder knop: alleen afschermen in de app-wisselaar.
struct LockView: View {
    let showButton: Bool
    @EnvironmentObject private var session: Session

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.iris.opacity(0.25), .clear], center: .top, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                BeheerLogo(size: 30)
                if showButton {
                    Button {
                        Task { await session.unlock() }
                    } label: {
                        Label("Ontgrendel met \(session.biometryName)", systemImage: session.biometryIcon)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8).frame(minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .task(id: showButton) {
            if showButton && !session.autoUnlockTried {
                session.autoUnlockTried = true
                await session.unlock()
            }
        }
    }
}
