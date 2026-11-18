import Foundation
import Security

/// Token in the Keychain, the signed-in user and a stable device id in UserDefaults.
final class AuthStore {
    static let shared = AuthStore()

    private let service = "xyz.synkmusic.app"
    private let lock = NSLock()
    private var cached: String??

    var token: String? {
        get {
            lock.lock(); defer { lock.unlock() }
            if let cached { return cached }
            let v = read()
            cached = .some(v)
            return v
        }
        set {
            lock.lock(); defer { lock.unlock() }
            cached = .some(newValue)
            if let newValue, !newValue.isEmpty { write(newValue) } else { delete() }
        }
    }

    var user: User? {
        get {
            guard let d = UserDefaults.standard.data(forKey: "synk.user") else { return nil }
            return try? JSONDecoder().decode(User.self, from: d)
        }
        set {
            if let newValue, let d = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(d, forKey: "synk.user")
            } else {
                UserDefaults.standard.removeObject(forKey: "synk.user")
            }
        }
    }

    var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: "synk.deviceId"), !id.isEmpty { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: "synk.deviceId")
        return id
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "token"]
    }

    private func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func write(_ v: String) {
        delete()
        var q = query
        q[kSecValueData as String] = Data(v.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    private func delete() { SecItemDelete(query as CFDictionary) }
}
