import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: Session
    @State private var push = PushService.shared
    @State private var testState: String?
    @State private var confirmLogoutAll = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { session.lockEnabled }, set: { on in Task { await session.setLockEnabled(on) } })) {
                    Label("Vergrendelen met \(session.biometryName)", systemImage: session.biometryIcon)
                }
                .disabled(!session.canLock)
            } header: {
                Text("Beveiliging")
            } footer: {
                #if os(macOS)
                Text("PasrBeheer vraagt om \(session.biometryName) bij het openen en als de app 5 minuten niet voorop stond.")
                #else
                Text("PasrBeheer vraagt om \(session.biometryName) bij het openen en elke keer dat je terugkomt in de app.")
                #endif
            }

            Section {
                switch push.permission {
                case .allowed:
                    Toggle("Nieuwe accounts", isOn: pref(\.signups))
                    Toggle("Account bevestigd", isOn: pref(\.confirmed))
                    Toggle("Account verwijderd", isOn: pref(\.deleted))
                    Toggle("Bot tegengehouden (max. 1 per uur)", isOn: pref(\.bots))
                    Toggle("Winkel aangevraagd", isOn: pref(\.requests))
                    Button {
                        Task {
                            testState = "Versturen…"
                            do { try await push.sendTest(); testState = "Verstuurd. De melding komt zo binnen." }
                            catch { testState = error.localizedDescription }
                        }
                    } label: { Label("Testmelding sturen", systemImage: "paperplane") }
                    if let testState { Text(testState).font(.footnote).foregroundStyle(Theme.muted) }
                case .denied:
                    Text("Meldingen staan uit voor PasrBeheer.").foregroundStyle(Theme.muted)
                    Button("Open instellingen") { push.openSystemSettings() }
                default:
                    Button { Task { await push.requestPermission() } } label: { Label("Meldingen aanzetten", systemImage: "bell.badge") }
                }
                if let e = push.lastError { Text(e).font(.footnote).foregroundStyle(Theme.coral) }
            } header: {
                Text("Pushmeldingen")
            } footer: {
                Text(push.registered ? "Dit apparaat is aangemeld. Meldingen bevatten nooit e-mailadressen of namen, alleen aantallen."
                                     : "Meldingen bevatten nooit e-mailadressen of namen, alleen aantallen.")
            }

            Section("Sessie") {
                if let exp = session.expiresAt {
                    LabeledContent("Ingelogd tot", value: exp.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(Locale(identifier: "nl_NL"))))
                }
                Button("Uitloggen") { session.logout() }
                Button("Overal uitloggen", role: .destructive) { confirmLogoutAll = true }
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.coral) }
            }

            Section("Links") {
                Link(destination: Config.beheerSite) { Label("beheer.pasr.nl", systemImage: "safari") }
                Link(destination: Config.website) { Label("pasr.nl", systemImage: "globe") }
                Link(destination: Config.supabaseDashboard) { Label("Supabase", systemImage: "server.rack") }
            }

            Section {
                MoreAppsCard()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text(MoreAppsText.current.section)
            }

            Section {
                LabeledContent("Versie", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(PushService.appBuild))")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Instellingen")
        .task { await push.refresh() }
        .confirmationDialog("Overal uitloggen?", isPresented: $confirmLogoutAll, titleVisibility: .visible) {
            Button("Overal uitloggen", role: .destructive) {
                Task {
                    do { try await session.logoutAll() } catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text("Alle sessies vervallen, ook op beheer.pasr.nl en je andere apparaten. Pushmeldingen moet je daarna opnieuw aanzetten.")
        }
    }

    private func pref(_ key: WritableKeyPath<PushPrefs, Bool>) -> Binding<Bool> {
        Binding(get: { push.prefs[keyPath: key] }, set: { v in push.setPref { $0[keyPath: key] = v } })
    }
}
