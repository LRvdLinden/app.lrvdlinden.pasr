import SwiftUI
import SwiftData

@main
struct PasrApp: App {
    let container = PasrStore.makeContainer()
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(PasrAppDelegate.self) private var appDelegate
    #endif
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.auto.rawValue

    init() {
        #if os(iOS)
        WatchLink.shared.activate()
        #endif
        NotificationRouter.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .environment(\.codeShield, ScreenShield.wrapper)
                .task {
                    PasrStore.purgeOldDeletions(in: container.mainContext)
                    await StoreCatalog.shared.refresh()
                    await UserPush.refreshIfAllowed()
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
    @State private var incomingTemp: IncomingTempShare?
    @State private var newStore: NewStore?
    @State private var invite: GroupService.Invite?
    @State private var seenInvites: Set<String> = []
    @Environment(\.modelContext) private var context
    private var groups = GroupService.shared
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
        // "Vind je Pasr leuk?": eerst een paar uur na het eerste gebruik, daarna hoogstens 1 keer per week
        .reviewPrompt(ready: !showSplash && onboarded && !locked && !covered && !cards.isEmpty && incoming == nil
                       && incomingTemp == nil && invite == nil)
        // A tapped notification (voucher reminder or "you're at the store") opens its card.
        .onReceive(NotificationCenter.default.publisher(for: .pasrOpenCard)) { _ in openFromNotification() }
        .onAppear { openFromNotification() }
        .onOpenURL { url in
            if let id = DeepLink.cardID(from: url) {
                openCardID = id
            } else if let token = TempShare.token(from: url) {
                incomingTemp = IncomingTempShare(token: token)
            } else if (url.host() == "pasr.nl" && url.path().hasPrefix("/uitnodiging")) || (url.scheme == "pasr" && url.host() == "uitnodiging") {
                Task { await GroupService.shared.sync(in: context) }   // de uitnodiging verschijnt hieronder
            } else if let shared = CardShare.decode(url) {
                incoming = IncomingShare(card: shared)
            }
        }
        .sheet(item: $incoming) { share in
            ReceiveCardSheet(shared: share.card)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasrOpenStore)) { _ in openStoreFromNotification() }
        .sheet(item: $newStore) { item in
            AddCardView(store: item.template)
        }
        .sheet(item: $incomingTemp) { share in
            ReceiveTempCardSheet(token: share.token)
        }
        // Uitnodiging voor een gedeelde Pasr: na inloggen of synchroniseren, op een rustig moment
        .sheet(item: $invite) { item in
            GroupInviteSheet(invite: item)
        }
        .onChange(of: groups.invites, initial: true) { _, _ in offerInvite() }
        .onChange(of: showSplash) { _, _ in offerInvite() }
        .onChange(of: onboarded) { _, _ in offerInvite() }
        .onChange(of: locked) { _, _ in offerInvite() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            TempShare.scrubExpired(in: context)
            await StoreCatalog.shared.refresh()
            await TempShare.refreshStatuses(in: context)
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

/// Een winkel uit een pushmelding, voor `.sheet(item:)`.
struct NewStore: Identifiable {
    let template: StoreTemplate
    var id: String { template.id }
}

extension RootView {
    fileprivate func openStoreFromNotification() {
        guard let id = NotificationRouter.pendingStoreID else { return }
        NotificationRouter.pendingStoreID = nil
        Task {
            if StoreTemplates.template(id: id) == nil { await StoreCatalog.shared.refresh(force: true) }
            if let template = StoreTemplates.template(id: id) { newStore = NewStore(template: template) }
        }
    }

    fileprivate func offerInvite() {
        guard invite == nil, !showSplash, onboarded, !locked, incoming == nil, incomingTemp == nil,
              let next = groups.invites.first(where: { !seenInvites.contains($0.id) }) else { return }
        seenInvites.insert(next.id)
        invite = next
    }

    fileprivate func openFromNotification() {
        guard let id = NotificationRouter.pendingCardID else { return }
        NotificationRouter.pendingCardID = nil
        openCardID = id
    }
}
