import Foundation
import Security

/// De sessie in de sleutelhanger, alleen op dit apparaat (refresh-tokens zijn eenmalig, dus nooit synchroniseren).
enum Keychain {
    static let service = "app.lrvdlinden.pasrzakelijk.account"

    /// Op de Mac de moderne sleutelhanger (zoals iOS), niet de oude login-sleutelhanger met toegangsvragen.
    private static var base: [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        #if os(macOS)
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }

    static func save<T: Encodable>(_ value: T, account: String = "session") {
        guard let data = try? JSONEncoder().encode(value) else { return }
        delete(account: account)
        let query = base.merging([kSecAttrAccount as String: account, kSecValueData as String: data,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]) { _, new in new }
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load<T: Decodable>(_ type: T.Type, account: String = "session") -> T? {
        let query = base.merging([kSecAttrAccount as String: account, kSecReturnData as String: true,
                                  kSecMatchLimit as String: kSecMatchLimitOne]) { _, new in new }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func delete(account: String = "session") {
        let query = base.merging([kSecAttrAccount as String: account]) { _, new in new }
        SecItemDelete(query as CFDictionary)
    }
}
