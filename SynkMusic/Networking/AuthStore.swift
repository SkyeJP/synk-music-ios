import Foundation
import Security

// Token persisted in the Keychain; device id in UserDefaults. Mirrors the
// Android AuthStore contract (token(), setToken(), deviceId()).
final class AuthStore {
    static let shared = AuthStore()

    private let service = "xyz.synkmusic.app"
    private let tokenKey = "token"
    private let deviceKey = "synk_device_id"

    var token: String? {
        get { keychainRead(tokenKey) }
        set {
            if let v = newValue, !v.isEmpty { keychainWrite(tokenKey, v) }
            else { keychainDelete(tokenKey) }
        }
    }

    var deviceId: String {
        if let existing = UserDefaults.standard.string(forKey: deviceKey) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: deviceKey)
        return fresh
    }

    private func keychainWrite(_ key: String, _ value: String) {
        keychainDelete(key)
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func keychainRead(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
