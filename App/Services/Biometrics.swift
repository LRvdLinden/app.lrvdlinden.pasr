import Foundation
import LocalAuthentication

/// Face ID / Touch ID / Optic ID, falling back to the device passcode.
enum Biometrics {
    static let appLockKey = "appLockEnabled"

    static var isAppLockEnabled: Bool { UserDefaults.standard.bool(forKey: appLockKey) }

    /// "Face ID", "Touch ID", "Optic ID" or "toegangscode", for labels.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "toegangscode")
        }
    }

    static var symbolName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "faceid"
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Asks for Face ID (or the passcode). Returns true when the person is verified.
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
