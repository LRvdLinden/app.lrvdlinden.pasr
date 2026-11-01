import SwiftUI

/// Inloggen, of de app zelf (tabbalk op de iPhone, zijbalk op iPad en Mac), met het vergrendelscherm erover.
struct RootView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.scenePhase) private var scenePhase
    @State private var push = PushService.shared
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if session.isSignedIn {
                main
            } else {
                LoginView()
            }
            if shielded {
                LockView(showButton: showUnlockButton)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.2), value: shielded)
        .onAppear { push.attach(session) }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                session.didEnterForeground()
                Task { await push.refresh() }
            case .background: session.didLeaveForeground()
            default:
                #if os(macOS)
                session.didLeaveForeground()
                #endif
                break
            }
        }
        .sheet(isPresented: Binding(get: { push.showPrompt && !session.isLocked }, set: { if !$0 { push.answerPrompt(false) } })) {
            PushPromptView()
                .presentationDetents([.medium])
                .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder private var main: some View {
        #if os(iOS)
        if sizeClass == .regular { SplitLayout() } else { TabLayout() }
        #else
        SplitLayout()
        #endif
    }

    private var showUnlockButton: Bool {
        #if os(iOS)
        session.isLocked && scenePhase == .active
        #else
        session.isLocked
        #endif
    }

    /// Vergrendeld; op iPhone/iPad ook afgeschermd in de app-wisselaar.
    private var shielded: Bool {
        guard session.isSignedIn, session.lockEnabled else { return false }
        #if os(iOS)
        return session.isLocked || scenePhase != .active
        #else
        return session.isLocked
        #endif
    }
}

struct TabLayout: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        TabView(selection: $session.section) {
            ForEach(AppSection.allCases) { s in
                NavigationStack { SectionContent(section: s) }
                    .tabItem { Label(s.title, systemImage: s.icon) }
                    .tag(s)
            }
        }
    }
}

struct SplitLayout: View {
    @EnvironmentObject private var session: Session
    @State private var visibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            List(selection: Binding<AppSection?>(get: { session.section }, set: { if let s = $0 { session.section = s } })) {
                Section {
                    ForEach(AppSection.allCases) { s in Label(s.title, systemImage: s.icon).tag(s) }
                } header: {
                    BeheerLogo(size: 18).padding(.vertical, 8).textCase(nil).foregroundStyle(.primary)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            NavigationStack { SectionContent(section: session.section) }
                .id(session.section)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct SectionContent: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .overview: OverviewView()
        case .insights: InsightsView()
        case .accounts: AccountsView()
        case .settings: SettingsView()
        }
    }
}

/// Uitleg vóór de systeemvraag voor meldingen.
struct PushPromptView: View {
    @State private var push = PushService.shared

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.iris2)
                .padding(.top, 26)
            Text("Meldingen aanzetten?").font(.title2.bold())
            Text("Krijg een melding bij een nieuw account, een verwijderd account of als er een bot is tegengehouden. Per soort zet je ze aan of uit in Instellingen.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 24)
            Spacer()
            Button { push.answerPrompt(true) } label: {
                Text("Aanzetten").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            Button("Niet nu") { push.answerPrompt(false) }
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .frame(minWidth: 360, minHeight: 380)
    }
}
