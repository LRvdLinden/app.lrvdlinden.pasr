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
                              && store.pendingInvite == nil && modals.openCount == 0 && !modals.scanning)
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
}

private struct TrackModal: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { ModalTracker.shared.openCount += 1 }
            .onDisappear { ModalTracker.shared.openCount = max(0, ModalTracker.shared.openCount - 1) }
    }
}

extension View {
    /// Op de inhoud van elke sheet: telt mee als "niet rustig".
    func trackModal() -> some View { modifier(TrackModal()) }
}
