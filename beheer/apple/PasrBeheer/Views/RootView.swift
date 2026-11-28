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
        .task(id: "\(session.isSignedIn)|\(session.refreshTick)") { await session.refreshMailBadge() }
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
        TabView(selection: Binding<PhoneTab>(
            get: { PhoneTab(session.section) },
            set: { if $0 != PhoneTab(session.section) { session.section = $0.firstSection } }
        )) {
            NavigationStack { OverviewView() }
                .tabItem { Label(LocalizedStringKey(PhoneTab.today.title), systemImage: PhoneTab.today.icon) }
                .tag(PhoneTab.today)
            NavigationStack { PeopleView() }
                .tabItem { Label(LocalizedStringKey(PhoneTab.people.title), systemImage: PhoneTab.people.icon) }
                .tag(PhoneTab.people)
            NavigationStack { MessagesView() }
                .tabItem { Label(LocalizedStringKey(PhoneTab.messages.title), systemImage: PhoneTab.messages.icon) }
                .badge(session.mailUnread + session.mailUnreadOwners)
                .tag(PhoneTab.messages)
            NavigationStack { InsightsView() }
                .tabItem { Label(LocalizedStringKey(PhoneTab.figures.title), systemImage: PhoneTab.figures.icon) }
                .tag(PhoneTab.figures)
            MoreView()
                .tabItem { Label(LocalizedStringKey(PhoneTab.more.title), systemImage: PhoneTab.more.icon) }
                .tag(PhoneTab.more)
        }
    }
}

struct SplitLayout: View {
    @EnvironmentObject private var session: Session
    @State private var visibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            List(selection: Binding<AppSection?>(get: { session.section }, set: { if let s = $0 { session.section = s } })) {
                ForEach(Array(AppSection.groups.enumerated()), id: \.offset) { i, g in
                    Section {
                        ForEach(g.items) { s in
                            Label(LocalizedStringKey(s.title), systemImage: s.icon).badge(unread(s)).tag(s)
                        }
                    } header: {
                        if i == 0 {
                            BeheerLogo(size: 18).padding(.vertical, 8).textCase(nil).foregroundStyle(.primary)
                        } else if let t = g.title {
                            Text(LocalizedStringKey(t))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            NavigationStack { SectionContent(section: session.section) }
                .id(session.section)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func unread(_ s: AppSection) -> Int {
        switch s {
        case .supportMail: session.mailUnread
        case .ownersMail: session.mailUnreadOwners
        default: 0
        }
    }
}

struct SectionContent: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .overview: OverviewView()
        case .insights: InsightsView()
        case .accounts: AccountsView()
        case .stores: StoresView()
        case .news: NewsView()
        case .businesses: BusinessesView()
        case .supportMail: MailView(box: .pasr)
        case .ownersMail: MailView(box: .zakelijk)
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
