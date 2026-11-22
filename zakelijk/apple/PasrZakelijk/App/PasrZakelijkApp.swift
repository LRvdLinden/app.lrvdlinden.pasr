import SwiftUI

@main
struct PasrZakelijkApp: App {
    @UIApplicationDelegateAdaptor(ZakelijkAppDelegate.self) private var appDelegate
    @AppStorage(AppearanceSetting.key) private var appearance: AppearanceSetting = .system
    @State private var store = BusinessStore.shared
    @State private var account = Account.shared

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(store)
                .environment(account)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
                .onOpenURL { store.handle(url: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { store.handle(url: url) }
                }
        }
    }
}

/// Splashscreen, Face ID-slot en afdekking in de appkiezer om de app heen (zelfde opzet als Pasr).
struct AppShell: View {
    @Environment(BusinessStore.self) private var store
    @Environment(Account.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Biometrics.appLockKey) private var appLock = false
    @State private var showSplash = true
    @State private var locked = Biometrics.isAppLockEnabled
    @State private var covered = false
    @State private var modals = ModalTracker.shared
    @State private var links = NotificationLink.shared
    @State private var safariLink: IdentifiedURL?

    var body: some View {
        ZStack {
            RootView()
                .opacity(showSplash || locked ? 0 : 1)
                .accessibilityHidden(showSplash || locked)
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
            // verbergt de zaakgegevens in de appkiezer
            if covered && !showSplash {
                PrivacyCover().zIndex(3)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onChange(of: showSplash || locked, initial: true) { _, hidden in
            ModalTracker.shared.locked = hidden
            openPendingLink()
        }
        // Link uit een getikte melding (pas na splash en Face ID-slot)
        .onChange(of: links.pending) { _, _ in openPendingLink() }
        #if canImport(SafariServices)
        .sheet(item: $safariLink) { item in
            SafariView(url: item.url).ignoresSafeArea().trackModal()
        }
        #endif
        // Meldingen: één keer vragen op een rustig moment (zaak goedgekeurd, niets open); daarna token en apparaat melden
        .task(id: !showSplash && !locked && account.isSignedIn && store.current?.isApproved == true && modals.isCalm) {
            guard !showSplash, !locked, account.isSignedIn, store.current?.isApproved == true, modals.isCalm else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await ZakelijkPush.askOnce()
        }
        .task(id: "\(scenePhase == .active)|\(account.session?.userID ?? "-")") {
            guard scenePhase == .active, account.isSignedIn else { return }
            await ZakelijkPush.refreshIfAllowed()
            await DeviceRegistry.registerIfNeeded()
        }
        // Beoordelingsvraag alleen op een rustig moment: niet tijdens splash, slot, inloggen, wachten op goedkeuring,
        // een uitnodiging, een sheet of dialoog, of terwijl er een klant geholpen wordt.
        .reviewPrompt(isCalm: !showSplash && !locked && !covered && account.isSignedIn && store.current?.isApproved == true
                      && store.pendingInvite == nil && modals.isCalm)
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

extension AppShell {
    /// Een link van pasr.nl die de app kent (uitnodiging voor medewerkers) gaat naar die plek in de app; elke andere
    /// https-link opent in Safari in de app (SFSafariViewController).
    fileprivate func openPendingLink() {
        guard let url = links.pending, !showSplash, !locked else { return }
        links.pending = nil
        if store.handles(url: url) {
            store.handle(url: url)
            return
        }
        #if canImport(SafariServices)
        safariLink = IdentifiedURL(url: url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

/// Houdt bij of er een sheet open staat of de scanner bezig is (geen beoordelingsvraag op zo'n moment).
@MainActor
@Observable
final class ModalTracker {
    static let shared = ModalTracker()
    var openCount = 0
    var scanning = false
    /// Dialogen en bezig-momenten (bevestigen, code typen, zoeken) die geen sheet zijn.
    var busyCount = 0
    /// Splashscreen of Face ID-slot staat voor de app: geen sheets (uitnodiging) en geen beoordelingsvraag.
    var locked = false
    var isCalm: Bool { openCount == 0 && !scanning && busyCount == 0 }
}

private struct TrackModal: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { ModalTracker.shared.openCount += 1 }
            .onDisappear { ModalTracker.shared.openCount = max(0, ModalTracker.shared.openCount - 1) }
    }
}

/// Zolang `active` waar is, telt het scherm als "niet rustig" (bijv. een bevestigingsvraag of typen).
private struct BusyWhile: ViewModifier {
    let active: Bool
    @State private var counted = false

    func body(content: Content) -> some View {
        content
            .onChange(of: active, initial: true) { _, now in set(now) }
            .onDisappear { set(false) }
    }

    private func set(_ on: Bool) {
        guard on != counted else { return }
        counted = on
        ModalTracker.shared.busyCount = max(0, ModalTracker.shared.busyCount + (on ? 1 : -1))
    }
}

extension View {
    /// Op de inhoud van elke sheet: telt mee als "niet rustig".
    func trackModal() -> some View { modifier(TrackModal()) }
    /// Voor dialogen en bezig-momenten die geen sheet zijn.
    func busyWhile(_ active: Bool) -> some View { modifier(BusyWhile(active: active)) }
}
