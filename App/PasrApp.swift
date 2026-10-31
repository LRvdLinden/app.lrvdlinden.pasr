import SwiftUI
import SwiftData

@main
struct PasrApp: App {
    let container = PasrStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .task {
                    PasrStore.purgeOldDeletions(in: container.mainContext)
                    await LogoService.fillMissing(in: container.mainContext)
                }
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 460, height: 820)
        .windowResizability(.contentMinSize)
        #endif
    }
}

struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            WalletView()
                .opacity(showSplash ? 0 : 1)
            if showSplash {
                SplashView { withAnimation(.easeOut(duration: 0.35)) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .background(Brand.ink.ignoresSafeArea())
    }
}
