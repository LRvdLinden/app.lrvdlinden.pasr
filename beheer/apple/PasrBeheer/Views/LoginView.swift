import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: Session
    @State private var user = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case user, password }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.iris.opacity(0.3), .clear], center: .top, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BeheerLogo(size: 28).padding(.bottom, 12)
                    Text("Inloggen").font(.title2.bold())
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gebruikersnaam").font(.footnote).foregroundStyle(Theme.muted)
                        TextField("", text: $user)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .focused($focus, equals: .user)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                            .modifier(FieldStyle())
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Wachtwoord").font(.footnote).foregroundStyle(Theme.muted)
                        SecureField("", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { Task { await login() } }
                            .modifier(FieldStyle())
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Theme.coral)
                    } else if let msg = session.loginMessage {
                        Text(msg).font(.footnote).foregroundStyle(Theme.muted)
                    }
                    Button {
                        Task { await login() }
                    } label: {
                        ZStack {
                            Text("Inloggen").fontWeight(.semibold).opacity(busy ? 0 : 1)
                            if busy { ProgressView() }
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || user.isEmpty || password.isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(28)
                .background(Theme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line))
                .frame(maxWidth: 420)
                .padding(.horizontal, 16)
                .padding(.top, 80)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { focus = .user }
    }

    private func login() async {
        guard !busy, !user.isEmpty, !password.isEmpty else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await session.login(user: user.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(Color(hex: 0x11131A), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
    }
}
