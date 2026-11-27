import Foundation
import LocalAuthentication

/// Face ID / Touch ID / Optic ID, met de toegangscode als terugval (zelfde als in Pasr).
enum Biometrics {
    static let appLockKey = "security.appLock"

    static var isAppLockEnabled: Bool { UserDefaults.standard.bool(forKey: appLockKey) }

    /// "Face ID", "Touch ID", "Optic ID" of "toegangscode", voor labels.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        #if os(iOS)
        case .opticID: return "Optic ID"
        #endif
        #if os(macOS)
        default: return String(localized: "wachtwoord")
        #else
        default: return String(localized: "toegangscode")
        #endif
        }
    }

    static var symbolName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: return "touchid"
        #if os(iOS)
        case .opticID: return "opticid"
        #endif
        #if os(macOS)
        default: return "lock.fill"
        #else
        default: return "faceid"
        #endif
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Vraagt om Face ID (of de toegangscode). Geeft true als de persoon is herkend.
    @MainActor
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Annuleer")
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
