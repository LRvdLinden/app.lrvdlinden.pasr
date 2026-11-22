import SwiftUI

@main
struct PasrZakelijkApp: App {
    @AppStorage(AppearanceSetting.key) private var appearance: AppearanceSetting = .system
    @State private var store = BusinessStore.shared
    @State private var account = Account.shared
    @State private var modals = ModalTracker.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(account)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
                .onOpenURL { store.handle(url: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { store.handle(url: url) }
                }
                .reviewPrompt(isCalm: account.isSignedIn && store.current?.isApproved == true
                              && store.pendingInvite == nil && modals.isCalm)
        }
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
