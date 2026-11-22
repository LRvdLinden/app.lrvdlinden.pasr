import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct PasrApp: App {
    let container = PasrStore.app
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
                // bonnetje gekozen in Spotlight ("PLUS bon")
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let id = (activity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(UUID.init) {
                        NotificationRouter.pendingReceiptID = id
                    }
                }
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
    @State private var incomingBusiness: IncomingBusinessCard?
    @Environment(\.openURL) private var openURL
    @State private var newStore: NewStore?
    /// Link uit een pushmelding: wacht tot splash, welkomst en ontgrendelen klaar zijn.
    @State private var pendingLink: URL?
    @State private var safariLink: IdentifiedURL?
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
                       && incomingTemp == nil && invite == nil && incomingBusiness == nil)
        // A tapped notification (voucher reminder or "you're at the store") opens its card.
        .onReceive(NotificationCenter.default.publisher(for: .pasrOpenCard)) { _ in openFromNotification() }
        .onAppear {
            openFromNotification()
            openNewsFromNotification()
        }
        .onOpenURL { url in handle(url) }
        // Universele links (pasr.nl/kaart, /tijdelijk, /uitnodiging) komen soms als NSUserActivity binnen
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { handle(url) }
        }
        .sheet(item: $incoming) { share in
            ReceiveCardSheet(shared: share.card)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasrOpenStore)) { _ in openStoreFromNotification() }
        .onReceive(NotificationCenter.default.publisher(for: .pasrOpenNews)) { _ in openNewsFromNotification() }
        .onReceive(NotificationCenter.default.publisher(for: .pasrOpenLink)) { note in
            if let url = note.object as? URL { handle(url) }
        }
        .sheet(item: $incomingBusiness) { item in
            JoinBusinessSheet(cardID: item.cardID, memberCode: item.memberCode)
        }
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
        #if canImport(SafariServices)
        .sheet(item: $safariLink) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
        #endif
        .onChange(of: showSplash) { _, _ in openPendingLink() }
        .onChange(of: onboarded) { _, _ in openPendingLink() }
        .onChange(of: locked) { _, _ in openPendingLink() }
        .onChange(of: groups.invites, initial: true) { _, _ in offerInvite() }
        .onChange(of: showSplash) { _, _ in offerInvite() }
        .onChange(of: onboarded) { _, _ in offerInvite() }
        .onChange(of: locked) { _, _ in offerInvite() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // eigen stempelkaarten (build 42) worden klantenkaarten; alleen de zaak zet nog stempels
            if OwnStampMigration.run(cards) > 0 { try? context.save() }
            TempShare.scrubExpired(in: context)
            await StoreCatalog.shared.refresh()
            await TempShare.refreshStatuses(in: context)
            await BusinessCards.refreshAll(in: context)
            await WalletPass.upgradeExistingPasses(cards)
            await StorePush.syncIfEnabled()
            await Birthday.syncWithAccount()
            await Birthday.reschedule(cards)
            await DeviceRegistry.registerIfNeeded()
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
    /// Een link naar Pasr: kaart, tijdelijke kaart, uitnodiging of blijvend gedeelde kaart. Staat er nog een venster
    /// open (bijvoorbeeld een kaart wijzigen), dan gaat dat eerst dicht, anders kan iOS het nieuwe niet tonen.
    fileprivate func handle(_ url: URL) {
        if let id = DeepLink.cardID(from: url) {
            openCardID = id
            return
        }
        // zakelijke stempelkaart: pasr.nl/zakelijk/kaart/#<id> of pasr://zakelijk/kaart#<id>
        if let businessID = BusinessLink.cardID(from: url) {
            let code = BusinessLink.memberCode(from: url)
            present { incomingBusiness = IncomingBusinessCard(cardID: businessID, memberCode: code) }
            return
        }
        let isTemp = (url.host() == "pasr.nl" && url.path().hasPrefix("/tijdelijk")) || (url.scheme == "pasr" && url.host() == "tijdelijk")
        if isTemp {
            // ook een onvolledige link tonen we (met "Deze link werkt niet"), zodat er nooit niets gebeurt
            present { incomingTemp = IncomingTempShare(token: TempShare.token(from: url) ?? "") }
        } else if (url.host() == "pasr.nl" && url.path().hasPrefix("/uitnodiging")) || (url.scheme == "pasr" && url.host() == "uitnodiging") {
            Task { await GroupService.shared.sync(in: context) }   // de uitnodiging verschijnt hieronder
        } else if let shared = CardShare.decode(url) {
            present { incoming = IncomingShare(card: shared) }
        }
    }

    /// Eerst open vensters sluiten, dan tonen (twee vensters tegelijk lukt niet; dan gebeurde er niets).
    fileprivate func present(_ show: @escaping () -> Void) {
        NotificationCenter.default.post(name: .pasrCloseSheets, object: nil)
        newStore = nil
        invite = nil
        safariLink = nil
        incoming = nil
        incomingTemp = nil
        incomingBusiness = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            show()
        }
    }

    fileprivate func openStoreFromNotification() {
        guard let id = NotificationRouter.pendingStoreID else { return }
        NotificationRouter.pendingStoreID = nil
        Task {
            if StoreTemplates.template(id: id) == nil { await StoreCatalog.shared.refresh(force: true) }
            if let template = StoreTemplates.template(id: id) { newStore = NewStore(template: template) }
        }
    }

    /// Pushmelding "Nieuws over mijn kaarten": je kaart van die winkel, anders Kaart toevoegen bij die winkel.
    fileprivate func openNewsFromNotification() {
        guard let news = NotificationRouter.pendingNews else { return }
        NotificationRouter.pendingNews = nil
        if let store = news.store {
            if let card = cards.alphabetical().first(where: { $0.templateID == store && !$0.isTemporary }) {
                openCardID = card.id
                return
            }
            NotificationRouter.pendingStoreID = store
        } else if let url = news.url {
            pendingLink = url
            openPendingLink()
        }
    }

    /// Link uit een melding, pas als de app klaar is (geen splash, welkomst of vergrendeling). Een link van pasr.nl die
    /// Pasr zelf kent (kaart, tijdelijke kaart, uitnodiging, zakelijke stempelkaart) gaat naar die plek in de app; elke
    /// andere https-link opent in Safari in de app (SFSafariViewController).
    fileprivate func openPendingLink() {
        guard let url = pendingLink, !showSplash, onboarded, !locked else { return }
        pendingLink = nil
        if Self.appHandles(url) {
            handle(url)
            return
        }
        #if canImport(SafariServices)
        present { safariLink = IdentifiedURL(url: url) }
        #else
        openURL(url)
        #endif
    }

    /// Kent Pasr deze link zelf (dezelfde regels als `handle`)?
    static func appHandles(_ url: URL) -> Bool {
        if DeepLink.cardID(from: url) != nil || BusinessLink.cardID(from: url) != nil { return true }
        guard url.host()?.lowercased() == "pasr.nl" else { return false }
        let path = url.path()
        if path.hasPrefix("/tijdelijk") || path.hasPrefix("/uitnodiging") { return true }
        return CardShare.decode(url) != nil
    }

    fileprivate func offerInvite() {
        guard invite == nil, !showSplash, onboarded, !locked, incoming == nil, incomingTemp == nil, incomingBusiness == nil,
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
