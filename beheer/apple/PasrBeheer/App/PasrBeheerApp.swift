import SwiftUI

@main
struct PasrBeheerApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @StateObject private var session = Session()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            root.frame(minWidth: 880, minHeight: 600)
        }
        .defaultSize(width: 1120, height: 780)
        .windowResizability(.contentMinSize)
        .commands { BeheerCommands(session: session) }

        Settings {
            NavigationStack { SettingsView() }
                .environmentObject(session)
                .preferredColorScheme(.dark)
                .tint(Theme.iris)
                .frame(width: 520, height: 620)
        }
        #else
        WindowGroup { root }
        #endif
    }

    private var root: some View {
        RootView()
            .environmentObject(session)
            .preferredColorScheme(.dark)
            .tint(Theme.iris)
            .onOpenURL { session.open($0) }
    }
}

#if os(macOS)
/// Menubalk: Vernieuwen (⌘R) en de onderdelen (⌘1 … ⌘3).
struct BeheerCommands: Commands {
    let session: Session

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Beheer") {
            Button("Vernieuwen") { Task { @MainActor in session.requestRefresh() } }
                .keyboardShortcut("r", modifiers: .command)
            Divider()
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { i, s in
                Button(s.title) { Task { @MainActor in session.section = s } }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
            }
        }
        CommandGroup(replacing: .help) {
            Button("beheer.pasr.nl") { NSWorkspace.shared.open(Config.beheerSite) }
            Button("pasr.nl") { NSWorkspace.shared.open(Config.website) }
            Button("Supabase") { NSWorkspace.shared.open(Config.supabaseDashboard) }
        }
    }
}
#endif
