import SwiftUI
import SwiftData

@main
struct PasrApp: App {
    let container = PasrStore.makeContainer()

    init() {
        #if os(iOS)
        WatchLink.shared.activate()
        #endif
    }

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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Biometrics.appLockKey) private var appLock = false
    @State private var showSplash = true
    @AppStorage("pasr.onboarded") private var onboarded = false
    @State private var locked = Biometrics.isAppLockEnabled
    @State private var covered = false
    @State private var openCardID: UUID?
    @State private var incoming: IncomingShare?

    var body: some View {
        ZStack {
            WalletView(openCardID: $openCardID)
                .accountSync()
                .opacity(showSplash || locked || !onboarded ? 0 : 1)
            if !onboarded && !showSplash {
                OnboardingView { withAnimation(.easeOut(duration: 0.3)) { onboarded = true } }
                    .transition(.opacity)
                    .zIndex(1.5)
            }
            if locked && !showSplash {
                LockView { withAnimation(.easeOut(duration: 0.25)) { locked = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
            if showSplash {
                SplashView { withAnimation(.easeOut(duration: 0.35)) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(2)
            }
            // Hides the cards in the app switcher.
            if covered && !showSplash {
                Brand.ink.ignoresSafeArea().overlay {
                    Text("pasr")
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(Brand.gradient)
                }
                .zIndex(3)
            }
        }
        .background(Brand.ink.ignoresSafeArea())
        .onOpenURL { url in
            if let id = DeepLink.cardID(from: url) {
                openCardID = id
            } else if let shared = CardShare.decode(url) {
                incoming = IncomingShare(card: shared)
            }
        }
        .sheet(item: $incoming) { share in
            ReceiveCardSheet(shared: share.card)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                if appLock { locked = true }
                covered = appLock
            case .inactive:
                covered = appLock
            case .active:
                covered = false
            @unknown default:
                break
            }
        }
    }
}
