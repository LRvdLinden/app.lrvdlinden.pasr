import SwiftUI
import AppKit
import UserNotifications
import Observation

/// Pasr Zakelijk voor de Mac (native SwiftUI, macOS 14+). Zelfde account, zaken, API en teksten als de iOS-app;
/// eigen vensters: het hoofdvenster met zijbalk (meerdere vensters kan), een Scannen-venster en Instellingen (⌘,).
@main
struct PasrZakelijkMacApp: App {
    @NSApplicationDelegateAdaptor(ZakelijkMacAppDelegate.self) private var appDelegate
    @AppStorage(AppearanceSetting.key) private var appearance: AppearanceSetting = .system
    @State private var store = BusinessStore.shared
    @State private var account = Account.shared

    var body: some Scene {
        WindowGroup(id: MacWindows.main) {
            MacShell { RootView() }
                .environment(store)
                .environment(account)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
                .frame(minWidth: 900, minHeight: 600)
                .onOpenURL { store.handle(url: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { store.handle(url: url) }
                }
        }
        .defaultSize(width: 1180, height: 780)
        .commands { MacMenuCommands() }

        // Scannen in een eigen venster (⇧⌘S), handig naast het hoofdvenster aan de kassa
        Window(Text("Scannen"), id: MacWindows.scanner) {
            MacShell { MacScannerWindow() }
                .environment(store)
                .environment(account)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
                .frame(minWidth: 520, minHeight: 620)
        }
        .defaultSize(width: 560, height: 720)

        Settings {
            MacSettingsWindow()
                .environment(store)
                .environment(account)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
        }
    }
}

enum MacWindows {
    /// Hoofdvenster (meerdere kan: Archief › Nieuw venster).
    static let main = "main"
    static let scanner = "scanner"
}

/// Opdrachten uit de menubalk naar het voorste venster.
@MainActor
@Observable
final class MacCommandCenter {
    static let shared = MacCommandCenter()
    var newItem: MacNewItem?
    var searchTick = 0
}

/// Menubalk: Archief › Nieuw (⌘N), Zoeken (⌘F), Scannen (⇧⌘S) en Ga naar (⌘1…).
struct MacMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nieuwe stempelkaart") { MacCommandCenter.shared.newItem = .stampCard }
                .keyboardShortcut("n", modifiers: .command)
            Menu("Nieuw") {
                MacNewMenuItems()
            }
            Divider()
            Button("Nieuw venster") { openWindow(id: MacWindows.main) }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }
        CommandGroup(after: .textEditing) {
            Button("Zoek in je zaak") { MacCommandCenter.shared.searchTick += 1 }
                .keyboardShortcut("f", modifiers: .command)
        }
        CommandMenu(Text("Zaak")) {
            Button("Scannen") { openWindow(id: MacWindows.scanner) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button("Vandaag") { AppNavigator.shared.request = .init(section: .vandaag) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Stempelkaarten") { AppNavigator.shared.request = .init(section: .stempelkaarten) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Klantenkaarten") { AppNavigator.shared.request = .init(section: .klantenkaarten) }
                .keyboardShortcut("3", modifiers: .command)
            Button("Tickets") { AppNavigator.shared.request = .init(section: .tickets) }
                .keyboardShortcut("4", modifiers: .command)
            Button("Gezamenlijke acties") { AppNavigator.shared.request = .init(section: .gezamenlijkeActies) }
                .keyboardShortcut("5", modifiers: .command)
            Button("Inzichten") { AppNavigator.shared.request = .init(section: .inzichten) }
                .keyboardShortcut("6", modifiers: .command)
            Button("Medewerkers") { AppNavigator.shared.request = .init(section: .medewerkers) }
                .keyboardShortcut("7", modifiers: .command)
            Divider()
            Button("Gegevens verversen") {
                Task {
                    await BusinessStore.shared.load()
                    await WidgetSync.refresh(force: true)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Link("Hulp en contact", destination: URL(string: "https://pasr.nl/support/")!)
            Link("Pasr Zakelijk op pasr.nl", destination: URL(string: "https://pasr.nl/zakelijk/")!)
        }
    }
}

/// Scannen-venster: dezelfde ScanView als op iOS (camera, code typen, plakken, USB-barcodescanner).
struct MacScannerWindow: View {
    @Environment(BusinessStore.self) private var store
    @Environment(Account.self) private var account

    var body: some View {
        Group {
            if !account.isSignedIn {
                MacPlaceholder(text: "Log in in het hoofdvenster van Pasr Zakelijk.")
            } else if let business = store.current, business.isApproved {
                ScanView(business: business).id(business.id)
            } else if !store.loaded {
                ProgressView().task { await store.load() }
            } else {
                MacPlaceholder(text: "Je zaak is nog niet goedgekeurd. Stempels zetten kan pas daarna.")
            }
        }
        .navigationTitle(store.current.map { Text(verbatim: $0.name) } ?? Text("Scannen"))
    }
}

/// Instellingen-venster (⌘,): dezelfde Instellingen als op iOS.
struct MacSettingsWindow: View {
    @Environment(BusinessStore.self) private var store
    @Environment(Account.self) private var account

    var body: some View {
        Group {
            if account.isSignedIn, let business = store.current {
                SettingsView(business: business)
                    .environment(\.isEmbeddedPane, true)
            } else {
                MacPlaceholder(text: "Log in in het hoofdvenster van Pasr Zakelijk.")
            }
        }
        .frame(width: 560, height: 680)
    }
}

struct MacPlaceholder: View {
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 16) {
            ZakelijkLogo(size: 24)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

/// Om de app heen: vergrendelen met Touch ID (instelling "Vergrendelen"), meldingen, apparaat melden en de
/// beoordelingsvraag op een rustig moment (zelfde regels als iOS).
struct MacShell<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(BusinessStore.self) private var store
    @Environment(Account.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Biometrics.appLockKey) private var appLock = false
    @State private var locked = Biometrics.isAppLockEnabled && !MacLockState.unlockedThisSession
    @State private var modals = ModalTracker.shared
    @State private var links = NotificationLink.shared
    @State private var safariLink: IdentifiedURL?

    var body: some View {
        ZStack {
            content
                .opacity(locked ? 0 : 1)
                .accessibilityHidden(locked)
            if locked {
                LockView {
                    MacLockState.unlockedThisSession = true
                    withAnimation(.easeOut(duration: 0.25)) { locked = false }
                }
                .transition(.opacity)
            }
        }
        .background(Theme.bg)
        .onChange(of: locked, initial: true) { _, hidden in
            ModalTracker.shared.locked = hidden
            openPendingLink()
        }
        .onChange(of: links.pending) { _, _ in openPendingLink() }
        .sheet(item: $safariLink) { item in InAppBrowser(url: item.url).trackModal() }
        .task(id: !locked && account.isSignedIn && store.current?.isApproved == true && modals.isCalm) {
            guard !locked, account.isSignedIn, store.current?.isApproved == true, modals.isCalm else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await ZakelijkPush.askOnce()
        }
        .task(id: "\(scenePhase == .active)|\(account.session?.userID ?? "-")") {
            guard scenePhase == .active, account.isSignedIn else { return }
            await ZakelijkPush.refreshIfAllowed()
            await DeviceRegistry.registerIfNeeded()
            await WidgetSync.refresh()
        }
        .reviewPrompt(isCalm: !locked && account.isSignedIn && store.current?.isApproved == true
                      && store.pendingInvite == nil && modals.isCalm)
        // vergrendelen als alle vensters verborgen of geminimaliseerd zijn
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && appLock {
                MacLockState.unlockedThisSession = false
                locked = true
            }
        }
    }

    private func openPendingLink() {
        guard let url = links.pending, !locked else { return }
        links.pending = nil
        if store.handles(url: url) { store.handle(url: url) } else { safariLink = IdentifiedURL(url: url) }
    }
}

/// Eén keer ontgrendelen geldt voor alle vensters tot de app weer verborgen wordt.
enum MacLockState {
    static var unlockedThisSession = false
}

/// Appdelegate van de Mac: APNs-token (zelfde topic als iOS: app.lrvdlinden.pasrzakelijk) en meldingen.
final class ZakelijkMacAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in ZakelijkPush.didRegister(token: deviceToken) }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    /// Laatste venster dicht: de app blijft draaien voor het Scannen-venster en het Dock (zoals Mail).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if let type = notification.request.content.userInfo["type"] as? String, CommunityRouter.pushTypes.contains(type) {
            Task { @MainActor in
                if let business = BusinessStore.shared.current { await CommunityRouter.shared.refreshCount(business: business) }
            }
        }
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        ZakelijkNotificationRouter.open(response.notification.request.content.userInfo)
        Task { @MainActor in NSApplication.shared.activate() }
        completionHandler()
    }
}
