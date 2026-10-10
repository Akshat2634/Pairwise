import Foundation
import Security

struct SavedSession: Codable, Sendable { let token: String; let server: String }

enum SessionVault {
    private static let service = "app.internal.pairdesk.session"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "current"]
    }
    static func read() -> SavedSession? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        // Startup stays in the menu bar. A changed development signature may
        // require Keychain approval; fall back to explicit sign-in rather than
        // presenting a hidden, blocking authentication dialog on launch.
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SavedSession.self, from: data)
    }
    static func save(_ session: SavedSession) throws {
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(q as CFDictionary, nil)
            guard result == errSecSuccess else { throw vaultError(result) }
        } else if status != errSecSuccess { throw vaultError(status) }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
    private static func vaultError(_ status: OSStatus) -> APIError {
        APIError(status: Int(status), message: "Could not save the session securely in Keychain.")
    }
}
