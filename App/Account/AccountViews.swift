import SwiftUI

/// Sign in, create an account or reset the password, in one sheet.
struct AccountSheet: View {
    enum Mode { case signIn, signUp, forgot, checkInbox }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    private let onDone: () -> Void

    init(mode: Mode = .signUp, onDone: @escaping () -> Void = {}) {
        _mode = State(initialValue: mode)
        self.onDone = onDone
    }

    @State private var firstName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var website = ""        // honeypot: hidden, people leave it empty
    @State private var shownAt = Date.now
    @State private var busy = false
    @State private var message: String?
    @State private var info: String?
    @FocusState private var focus: Field?
    private enum Field { case name, email, password }

    private var account: AccountService { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if mode == .checkInbox {
                        checkInbox
                    } else {
                        form
                    }
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Brand.ink.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sluit") { dismiss() } }
            }
        }
        .onChange(of: mode) { _, _ in
            message = nil
            info = nil
            shownAt = .now
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: mode == .checkInbox ? "envelope.badge" : "person.crop.circle.badge.checkmark")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Brand.gradient)
                .padding(.bottom, 4)
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch mode {
        case .signIn: String(localized: "Inloggen")
        case .signUp: String(localized: "Maak je Pasr-account")
        case .forgot: String(localized: "Wachtwoord vergeten")
        case .checkInbox: String(localized: "Check je mail")
        }
    }

    private var subtitle: String {
        switch mode {
        case .signIn: String(localized: "Log in om je kaarten uit je account op dit apparaat te zetten.")
        case .signUp: String(localized: "Al je kaarten veilig en versleuteld in één account, op al je apparaten. Gratis.")
        case .forgot: String(localized: "Vul je e-mailadres in. Je krijgt een mail om een nieuw wachtwoord te kiezen.")
        case .checkInbox: String(localized: "We hebben een mail gestuurd naar \(email). Tik op de knop in die mail om je e-mailadres te bevestigen en log daarna hier in.")
        }
    }

    @ViewBuilder private var form: some View {
        VStack(spacing: 12) {
            if mode == .signUp {
                field("Voornaam", text: $firstName, field: .name, content: .givenName)
            }
            field("E-mailadres", text: $email, field: .email, content: .emailAddress)
            if mode != .forgot {
                SecureField("Wachtwoord", text: $password)
                    #if os(iOS)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    #endif
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .modifier(FieldStyle())
            }
            // Honeypot: invisible for people (and VoiceOver); a bot filling in every field fills this one too.
            TextField("Website (laat leeg)", text: $website)
                .autocorrectionDisabled()
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        if mode == .signUp {
            Text("Minstens 8 tekens. Je krijgt een mail om je e-mailadres te bevestigen.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.callout).foregroundStyle(Brand.coral)
        }
        if let info {
            Label(info, systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(Brand.mint)
        }
        Button(action: submit) {
            HStack {
                if busy { ProgressView().tint(.white) }
                Text(buttonTitle).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(Brand.iris)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(busy || !valid)

        VStack(spacing: 10) {
            switch mode {
            case .signUp:
                Button("Ik heb al een account") { mode = .signIn }
            case .signIn:
                Button("Wachtwoord vergeten?") { mode = .forgot }
                Button("Nog geen account? Maak er een") { mode = .signUp }
            case .forgot:
                Button("Terug naar inloggen") { mode = .signIn }
            case .checkInbox:
                EmptyView()
            }
        }
        .font(.callout.weight(.medium))
        .tint(Brand.iris)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var checkInbox: some View {
        VStack(spacing: 12) {
            Button {
                mode = .signIn
            } label: {
                Text("Ik heb bevestigd, inloggen").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent).tint(Brand.iris)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button("Mail opnieuw sturen") {
                Task {
                    do {
                        try await account.resendConfirmation(email: email)
                        info = String(localized: "Verstuurd. Kijk ook bij ongewenste mail.")
                    } catch { message = error.localizedDescription }
                }
            }
            .tint(Brand.iris)
            if let info { Text(info).font(.footnote).foregroundStyle(Brand.mint) }
            if let message { Text(message).font(.footnote).foregroundStyle(Brand.coral) }
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, field: Field, content: UITextContentTypeCompat) -> some View {
        TextField(title, text: text)
            .focused($focus, equals: field)
            .autocorrectionDisabled()
            .modifier(ContentTypeModifier(kind: content))
            .submitLabel(.next)
            .onSubmit {
                focus = field == .name ? .email : (mode == .forgot ? nil : .password)
                if mode == .forgot { submit() }
            }
            .modifier(FieldStyle())
    }

    private var buttonTitle: String {
        switch mode {
        case .signIn: String(localized: "Inloggen")
        case .signUp: String(localized: "Account maken")
        case .forgot: String(localized: "Stuur mail")
        case .checkInbox: ""
        }
    }

    private var valid: Bool {
        let mailOK = email.contains("@") && email.contains(".")
        switch mode {
        case .signUp: return mailOK && password.count >= 8 && !firstName.trimmingCharacters(in: .whitespaces).isEmpty
        case .signIn: return mailOK && !password.isEmpty
        case .forgot: return mailOK
        case .checkInbox: return true
        }
    }

    private func submit() {
        guard valid, !busy else { return }
        busy = true
        message = nil
        info = nil
        Task {
            defer { busy = false }
            do {
                switch mode {
                case .signUp:
                    let ms = Int(Date.now.timeIntervalSince(shownAt) * 1000)
                    let result = try await account.signUp(firstName: firstName, email: email, password: password,
                                                          honeypot: website, fillMilliseconds: ms)
                    if result == .signedIn { finish() } else { mode = .checkInbox }
                case .signIn:
                    try await account.signIn(email: email, password: password)
                    finish()
                case .forgot:
                    try await account.sendPasswordReset(email: email)
                    info = String(localized: "Als er een account met dit adres is, staat er nu een mail in je inbox.")
                case .checkInbox:
                    break
                }
            } catch {
                website = ""
                message = error.localizedDescription
            }
        }
    }

    private func finish() {
        onDone()
        dismiss()
    }
}

/// Text content types, without importing UIKit on macOS.
enum UITextContentTypeCompat { case givenName, emailAddress }

private struct ContentTypeModifier: ViewModifier {
    let kind: UITextContentTypeCompat
    func body(content: Content) -> some View {
        #if os(iOS)
        switch kind {
        case .givenName: content.textContentType(.givenName).textInputAutocapitalization(.words)
        case .emailAddress: content.textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
        }
        #else
        switch kind {
        case .givenName: content.textContentType(.givenName)
        case .emailAddress: content.textContentType(.emailAddress)
        }
        #endif
    }
}

private struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The account part of Settings.
struct AccountSettingsSection: View {
    @Environment(\.modelContext) private var context
    @State private var showAccount = false
    @State private var confirmDelete = false
    @State private var deletePrompt = false
    @State private var working = false
    @State private var error: String?
    private var account: AccountService { .shared }

    var body: some View {
        Section {
            if let session = account.session {
                LabeledContent("Account") {
                    VStack(alignment: .trailing) {
                        if let name = session.firstName { Text(name) }
                        Text(session.email).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task {
                        working = true
                        await CardSync.sync(in: context)
                        error = CardSync.lastError
                        working = false
                    }
                } label: {
                    HStack {
                        Label("Nu synchroniseren", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if working { ProgressView() }
                        else if let last = CardSync.lastSync(for: session.userID) {
                            Text(last, format: .relative(presentation: .named)).foregroundStyle(.secondary).font(.footnote)
                        }
                    }
                }
                Button("Uitloggen") { Task { await account.signOut() } }
                Button("Account verwijderen", role: .destructive) { confirmDelete = true }
            } else {
                Button { showAccount = true } label: {
                    Label("Inloggen of account maken", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(!AccountConfig.isConfigured)
            }
        } header: {
            Text("Pasr-account")
        } footer: {
            Text(error ?? footer)
        }
        .sheet(isPresented: $showAccount) {
            AccountSheet(mode: .signUp) { Task { await CardSync.sync(in: context) } }
        }
        .confirmationDialog("Account verwijderen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwijder mijn account", role: .destructive) {
                Task {
                    do { try await account.deleteAccount() } catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text("Je account en de kaarten die erin staan worden verwijderd. De kaarten op dit apparaat en in je iCloud blijven staan.")
        }
    }

    private var footer: String {
        if !AccountConfig.isConfigured {
            return String(localized: "Accounts komen binnenkort. Tot die tijd staan je kaarten in je eigen iCloud.")
        }
        return account.isSignedIn
            ? String(localized: "Je kaarten staan versleuteld in je account en zijn zo op al je apparaten, ook na een nieuwe telefoon. Uitloggen laat de kaarten op dit apparaat staan.")
            : String(localized: "Optioneel. Met een gratis account staan al je kaarten versleuteld op één plek en heb je ze op elk apparaat.")
    }
}
