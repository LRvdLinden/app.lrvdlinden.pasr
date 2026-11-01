import SwiftUI
import SwiftData

@main
struct PasrApp: App {
    let container = PasrStore.makeContainer()

    init() {
        #if os(iOS)
        WatchLink.shared.activate()
        #endif
        NotificationRouter.shared.activate()
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
    @Query(filter: #Predicate<Card> { $0.deletedAt == nil }) private var cards: [Card]

    var body: some View {
        ZStack {
            WalletView(openCardID: $openCardID)
                .accountSync()
                .reminders()
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
        // "Vind je Pasr leuk?": één keer per apparaat, een paar uur na het eerste gebruik
        .reviewPrompt(ready: !showSplash && onboarded && !locked && !covered && !cards.isEmpty && incoming == nil)
        // A tapped notification (voucher reminder or "you're at the store") opens its card.
        .onReceive(NotificationCenter.default.publisher(for: .pasrOpenCard)) { _ in openFromNotification() }
        .onAppear { openFromNotification() }
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

extension RootView {
    fileprivate func openFromNotification() {
        guard let id = NotificationRouter.pendingCardID else { return }
        NotificationRouter.pendingCardID = nil
        openCardID = id
    }
}
