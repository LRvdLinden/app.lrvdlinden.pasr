import SwiftUI

/// Welkom en inloggen met je Pasr-account (zelfde account als op pasr.nl/zakelijk).
struct WelcomeView: View {
    enum Mode { case signIn, signUp, forgot, checkInbox }

    @State private var mode: Mode = .signIn
    @State private var firstName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var honeypot = ""
    @State private var shownAt = Date.now
    @State private var busy = false
    @State private var message: String?
    @State private var info: String?
    @State private var success = false
    @FocusState private var focus: Field?
    private enum Field { case name, email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZakelijkLogo(size: 26)
                    .padding(.top, 24)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Digitale stempelkaarten voor je zaak")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Scan de kaart van je klant en zet een stempel. Alleen jij en je medewerkers kunnen stempels zetten.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    feature("qrcode.viewfinder", "Scannen aan de kassa", "Stempel erbij, beloning inwisselen of ongedaan maken.")
                    feature("person.2", "Medewerkers", "Nodig je team uit; zij zien alleen de scanner.")
                    feature("chart.xyaxis.line", "Overzicht en logboek", "Zie per dag wat er gebeurt en wie wat deed.")
                }
                .padding(.vertical, 4)
                if mode == .checkInbox { checkInbox } else { form }
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: success)
        .onChange(of: mode) { _, _ in
            message = nil
            info = nil
            shownAt = .now
        }
    }

    private func feature(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.mint)
                .frame(width: 34, height: 34)
                .background(Theme.mint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var title: LocalizedStringKey {
        switch mode {
        case .signIn: "Inloggen"
        case .signUp: "Account maken"
        case .forgot: "Wachtwoord vergeten"
        case .checkInbox: "Check je mail"
        }
    }

    @ViewBuilder private var form: some View {
        CardBox(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.title2.weight(.bold))
                if mode == .signIn {
                    Text("Log in met je Pasr-account. Ben je medewerker? Gebruik het account waarmee je de uitnodiging accepteert.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if mode == .signUp {
                    TextField("Voornaam", text: $firstName)
                        .textContentType(.givenName)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .fieldStyle()
                }
                TextField("E-mailadres", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(mode == .forgot ? .send : .next)
                    .fieldStyle()
                if mode != .forgot {
                    SecureField("Wachtwoord", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .fieldStyle()
                }
                if mode == .signUp {
                    // honeypot: onzichtbaar, mensen laten dit leeg
                    TextField("", text: $honeypot)
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                        .accessibilityHidden(true)
                }
                if let message {
                    Text(message).font(.subheadline).foregroundStyle(Theme.coral)
                }
                if let info {
                    Text(info).font(.subheadline).foregroundStyle(Theme.mint)
                }
                Button {
                    Task { await submit() }
                } label: {
                    if busy { ProgressView().tint(.white) } else { Text(buttonTitle) }
                }
                .buttonStyle(BigButtonStyle())
                .disabled(busy || !valid)
                .opacity(valid ? 1 : 0.6)

                HStack {
                    switch mode {
                    case .signIn:
                        Button("Account maken") { mode = .signUp }
                        Spacer()
                        Button("Wachtwoord vergeten?") { mode = .forgot }
                    default:
                        Button("Ik heb al een account") { mode = .signIn }
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .onSubmit {
            switch focus {
            case .name: focus = .email
            case .email: if mode == .forgot { Task { await submit() } } else { focus = .password }
            default: Task { await submit() }
            }
        }
        Text("Met een account ga je akkoord met de privacyverklaring van Pasr.")
            .font(.footnote).foregroundStyle(.secondary)
        Link(destination: URL(string: "https://pasr.nl/privacy/#stempelkaarten-van-ondernemers")!) {
            Label("Privacyverklaring", systemImage: "hand.raised")
        }
        .font(.footnote.weight(.semibold))
    }

    private var checkInbox: some View {
        CardBox(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "envelope.badge").font(.largeTitle).foregroundStyle(Theme.mint)
                Text("Check je mail").font(.title2.weight(.bold))
                Text("We hebben je een mail gestuurd. Tik op de knop in die mail om je e-mailadres te bevestigen en log daarna hier in.")
                    .foregroundStyle(.secondary)
                if let info { Text(info).font(.subheadline).foregroundStyle(Theme.mint) }
                if let message { Text(message).font(.subheadline).foregroundStyle(Theme.coral) }
                Button("Naar inloggen") { mode = .signIn }
                    .buttonStyle(BigButtonStyle())
                Button("Mail opnieuw sturen") {
                    Task {
                        do {
                            try await Account.shared.resendConfirmation(email: email)
                            info = String(localized: "Verstuurd. Kijk ook bij ongewenste mail.")
                        } catch { message = error.localizedDescription }
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var buttonTitle: LocalizedStringKey {
        switch mode {
        case .signIn: "Inloggen"
        case .signUp: "Account maken"
        case .forgot: "Stuur een link"
        case .checkInbox: "Inloggen"
        }
    }

    private var valid: Bool {
        let mailOK = email.contains("@") && email.contains(".")
        switch mode {
        case .signIn: return mailOK && !password.isEmpty
        case .signUp: return mailOK && password.count >= 8 && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
        case .forgot: return mailOK
        case .checkInbox: return true
        }
    }

    private func submit() async {
        guard valid, !busy else { return }
        busy = true
        message = nil
        info = nil
        defer { busy = false }
        do {
            switch mode {
            case .signIn:
                try await Account.shared.signIn(email: email, password: password)
                success.toggle()
            case .signUp:
                let ms = Int(Date.now.timeIntervalSince(shownAt) * 1000)
                let result = try await Account.shared.signUp(firstName: firstName, email: email, password: password,
                                                             honeypot: honeypot, fillMilliseconds: ms)
                if result == .checkInbox { mode = .checkInbox } else { success.toggle() }
            case .forgot:
                try await Account.shared.sendPasswordReset(email: email)
                info = String(localized: "Als er een account is met dit adres, krijg je een mail met een link om een nieuw wachtwoord te kiezen.")
            case .checkInbox:
                mode = .signIn
            }
        } catch {
            message = error.localizedDescription
        }
    }
}

extension View {
    /// Invoerveld in de stijl van Pasr.
    func fieldStyle() -> some View {
        self
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
