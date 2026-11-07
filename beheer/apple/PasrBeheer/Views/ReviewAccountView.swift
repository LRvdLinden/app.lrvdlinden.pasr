import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Review-account voor Apple App Review: een bevestigd account met drie voorbeeldkaarten en een gedeelde Pasr
/// "Gezin" met twee kaarten. Het wachtwoord kies je hier zelf (of laat je maken); de server bewaart het niet.
struct ReviewAccountView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var email = "review@pasr.nl"
    @State private var firstName = "App Review"
    @State private var password = ""
    @State private var showPassword = false
    @State private var reset = false
    @State private var busy = false
    @State private var result: String?
    @State private var error: String?

    private struct Response: Decodable {
        let created: Bool
        let email: String
        let cards: Int?
        let group_cards: Int?
    }

    private var valid: Bool {
        email.contains("@") && password.count >= 10
            && password.rangeOfCharacter(from: .letters) != nil && password.rangeOfCharacter(from: .decimalDigits) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-mailadres", text: $email)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Voornaam", text: $firstName)
                } footer: {
                    Text("Maakt een bevestigd account met drie voorbeeldkaarten en een gedeelde Pasr \u{201C}Gezin\u{201D} met twee kaarten.")
                }
                Section {
                    HStack {
                        Group {
                            if showPassword { TextField("Wachtwoord", text: $password) } else { SecureField("Wachtwoord", text: $password) }
                        }
                        .textContentType(.newPassword)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(showPassword ? "Verberg wachtwoord" : "Toon wachtwoord")
                    }
                    Button("Maak sterk wachtwoord", systemImage: "key.fill") {
                        password = Self.strongPassword()
                        showPassword = true
                    }
                    Button("Kopieer wachtwoord", systemImage: "doc.on.doc") { Self.copy(password) }
                        .disabled(password.isEmpty)
                } footer: {
                    Text("Minimaal 10 tekens, met letters en cijfers. Het wachtwoord wordt nergens bewaard; zet het in App Store Connect › App Review › Sign-in information.")
                }
                Section {
                    Toggle("Bestaat al: wachtwoord vervangen en kaarten terugzetten", isOn: $reset)
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.coral) }
                }
                if let result {
                    Section { Label(result, systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Review-account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sluit") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Maak") { Task { await create() } }.disabled(!valid) }
                }
            }
        }
    }

    private func create() async {
        busy = true
        defer { busy = false }
        error = nil
        result = nil
        do {
            let r = try await session.call("review_account",
                                           ["email": email, "password": password, "first_name": firstName, "reset": reset],
                                           as: Response.self)
            result = "\(r.created ? "Account gemaakt" : "Wachtwoord vervangen"): \(r.email), met \(r.cards ?? 3) kaarten en een gedeelde Pasr met \(r.group_cards ?? 2) kaarten."
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 16 tekens zonder verwarrende tekens (0/O, 1/l/I), altijd met hoofdletter, kleine letter en cijfer.
    static func strongPassword() -> String {
        let sets = Array("ABCDEFGHJKLMNPQRSTUVWXYZ"), lower = Array("abcdefghijkmnpqrstuvwxyz"), digits = Array("23456789")
        let all = sets + lower + digits
        var chars = [sets.randomElement()!, lower.randomElement()!, digits.randomElement()!]
        while chars.count < 16 { chars.append(all.randomElement()!) }
        return String(chars.shuffled())
    }

    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]],
                                      options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)])
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
